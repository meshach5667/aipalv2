"""Self-hosted streaming STT via faster-whisper."""

from __future__ import annotations

import asyncio
import logging
import math
import time
from typing import Any

import numpy as np

from ..config import Settings
from ..stt import _get_model

log = logging.getLogger("aipal.whisper_stream")

# One CPU inference job at a time across connections.
_inference_semaphore: asyncio.Semaphore | None = None


def _semaphore() -> asyncio.Semaphore:
    global _inference_semaphore
    if _inference_semaphore is None:
        _inference_semaphore = asyncio.Semaphore(1)
    return _inference_semaphore


class WhisperStreamingSTT:
    SAMPLE_RATE = 16000

    def __init__(self, settings: Settings) -> None:
        self._partial_interval_ms = settings.whisper_stream_partial_interval_ms
        self._final_beam_size = max(1, int(settings.whisper_beam_size or 1))
        self._buffer = bytearray()
        self._last_partial_text = ""
        self._last_partial_at = 0.0
        self._speech_active = False
        self._speech_t0: float | None = None
        self._first_partial_mono: float | None = None
        self._last_metrics: dict[str, int] = {}
        self._last_final_meta: dict[str, int | float | str] = {}
        self._partial_task: asyncio.Task[str] | None = None

    def reset(self) -> None:
        self._buffer.clear()
        self._last_partial_text = ""
        self._last_partial_at = 0.0
        self._speech_active = False
        self._speech_t0 = None
        self._first_partial_mono = None
        self._last_final_meta = {}
        if self._partial_task and not self._partial_task.done():
            self._partial_task.cancel()
        self._partial_task = None

    def consume_metrics(self) -> dict[str, int]:
        metrics = {**self._last_metrics, **self._last_final_meta}
        self._last_metrics = {}
        self._last_final_meta = {}
        return metrics

    async def on_speech_start(self) -> None:
        self._speech_active = True
        self._buffer.clear()
        self._last_partial_text = ""
        self._last_partial_at = 0.0
        self._speech_t0 = time.monotonic()
        self._first_partial_mono = None
        self._last_metrics = {}
        self._last_final_meta = {}

    async def feed_audio(self, pcm: bytes) -> str | None:
        """Buffer PCM during an active utterance only.

        Partial inference is throttled and runs in the background. That keeps
        the WebSocket receive loop hot while still surfacing transcript updates.
        """
        if not pcm or not self._speech_active:
            return None
        self._buffer.extend(pcm)
        now = time.monotonic()
        if self._partial_task and self._partial_task.done():
            try:
                partial = self._partial_task.result().strip()
            except Exception:
                partial = ""
            self._partial_task = None
            if partial and partial != self._last_partial_text:
                self._last_partial_text = partial
                if self._first_partial_mono is None:
                    self._first_partial_mono = now
                    if self._speech_t0 is not None:
                        self._last_metrics["stt_partial_ms"] = int((now - self._speech_t0) * 1000)
                return partial
        enough_audio = len(self._buffer) >= int(self.SAMPLE_RATE * 2 * 0.55)
        elapsed_ms = int((now - self._last_partial_at) * 1000) if self._last_partial_at else self._partial_interval_ms
        if enough_audio and self._partial_task is None and elapsed_ms >= self._partial_interval_ms:
            self._last_partial_at = now
            self._partial_task = asyncio.create_task(self._transcribe(beam_size=1))
        return None

    async def on_speech_end(self) -> str:
        self._speech_active = False
        if self._partial_task and not self._partial_task.done():
            self._partial_task.cancel()
            self._partial_task = None
        if self._speech_t0 is not None and self._first_partial_mono is not None:
            self._last_metrics["stt_partial_ms"] = int(
                (self._first_partial_mono - self._speech_t0) * 1000
            )
        if not self._buffer:
            self.reset()
            return ""
        text = await self._transcribe(beam_size=self._final_beam_size)
        meta = self._last_final_meta or {
            "stt_confidence": 1.0 if text else 0.0,
            "stt_no_speech_probability": 0.0 if text else 1.0,
        }
        self.reset()
        self._last_final_meta = meta
        return text

    async def _transcribe(self, *, beam_size: int) -> str:
        text, meta = await self._transcribe_with_meta(beam_size=beam_size)
        self._last_final_meta = meta
        return text

    async def _transcribe_with_meta(self, *, beam_size: int) -> tuple[str, dict[str, int | float | str]]:
        pcm = bytes(self._buffer)
        if len(pcm) < 320:  # ~10 ms at 16 kHz
            return "", {"stt_confidence": 0.0, "stt_no_speech_probability": 1.0}

        async with _semaphore():
            return await asyncio.to_thread(self._transcribe_sync, pcm, beam_size)

    def _transcribe_sync(self, pcm: bytes, beam_size: int) -> tuple[str, dict[str, Any]]:
        audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
        model = _get_model()
        try:
            segments, _ = model.transcribe(
                audio,
                language=None,
                beam_size=beam_size,
                vad_filter=True,
                condition_on_previous_text=False,
                initial_prompt=None,
            )
            rows = list(segments)
            text = " ".join(s.text.strip() for s in rows if s.text.strip()).strip()
            if self._looks_like_prompt_echo(text):
                return "", {
                    "stt_confidence": 0.0,
                    "stt_no_speech_probability": 1.0,
                    "stt_language": "prompt_echo",
                }
            if not rows:
                return text, {
                    "stt_confidence": 0.0,
                    "stt_no_speech_probability": 1.0,
                    "stt_language": "unknown",
                }
            avg_logprob = sum(float(getattr(s, "avg_logprob", -1.2) or -1.2) for s in rows) / len(rows)
            no_speech_probability = max(float(getattr(s, "no_speech_prob", 0.0) or 0.0) for s in rows)
            confidence = max(0.0, min(1.0, math.exp(avg_logprob)))
            return text, {
                "stt_confidence": round(confidence, 3),
                "stt_no_speech_probability": round(no_speech_probability, 3),
                "stt_avg_logprob": round(avg_logprob, 3),
            }
        except Exception as e:
            log.warning("Whisper streaming transcribe failed: %s", e)
            return "", {"stt_confidence": 0.0, "stt_no_speech_probability": 1.0}

    def _looks_like_prompt_echo(self, text: str) -> bool:
        lower = " ".join(text.lower().split())
        return "speaker may have" in lower and "preserve names" in lower

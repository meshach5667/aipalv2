"""Fish Audio ASR-backed streaming STT adapter.

The browser streams PCM frames, but Fish ASR is request/response. This adapter
buffers one utterance and sends a WAV at speech end while exposing the same
StreamingSTT protocol as the local Whisper adapter.
"""

from __future__ import annotations

import asyncio
import io
import logging
import time
import wave
from typing import Any

import httpx

from ..config import Settings

log = logging.getLogger("aipal.fish_stt")


class FishAudioStreamingSTT:
    SAMPLE_RATE = 16000

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._buffer = bytearray()
        self._speech_active = False
        self._speech_t0: float | None = None
        self._last_metrics: dict[str, int | float | str] = {}

    async def on_speech_start(self) -> None:
        self._buffer.clear()
        self._last_metrics = {}
        self._speech_active = True
        self._speech_t0 = time.monotonic()

    async def feed_audio(self, pcm: bytes) -> str | None:
        if pcm and self._speech_active:
            self._buffer.extend(pcm)
        return None

    async def on_speech_end(self) -> str:
        self._speech_active = False
        pcm = bytes(self._buffer)
        self._buffer.clear()
        if len(pcm) < int(self.SAMPLE_RATE * 2 * 0.25):
            self._last_metrics = {
                "stt_confidence": 0.0,
                "stt_no_speech_probability": 1.0,
                "stt_provider": "fish_audio",
            }
            return ""
        started = time.monotonic()
        try:
            text = await self._transcribe_wav(self._wav_bytes(pcm))
            self._last_metrics = {
                "stt_confidence": 0.82 if text else 0.0,
                "stt_no_speech_probability": 0.0 if text else 1.0,
                "stt_provider": "fish_audio",
                "stt_remote_ms": int((time.monotonic() - started) * 1000),
            }
            return text
        except Exception as exc:
            log.warning("Fish Audio ASR failed: %s", exc)
            self._last_metrics = {
                "stt_confidence": 0.0,
                "stt_no_speech_probability": 1.0,
                "stt_provider": "fish_audio",
                "stt_error": exc.__class__.__name__,
                "stt_remote_ms": int((time.monotonic() - started) * 1000),
            }
            return ""

    def consume_metrics(self) -> dict[str, int | float | str]:
        metrics = dict(self._last_metrics)
        self._last_metrics = {}
        return metrics

    def reset(self) -> None:
        self._buffer.clear()
        self._last_metrics = {}
        self._speech_active = False
        self._speech_t0 = None

    def _wav_bytes(self, pcm: bytes) -> bytes:
        out = io.BytesIO()
        with wave.open(out, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(self.SAMPLE_RATE)
            wav.writeframes(pcm)
        return out.getvalue()

    async def _transcribe_wav(self, wav_bytes: bytes) -> str:
        settings = self._settings
        api_key = settings.effective_fish_api_key
        if not api_key:
            raise RuntimeError("FISH_AUDIO_API_KEY is not configured")
        base_url = settings.effective_fish_base_url.rstrip("/")
        headers = {"Authorization": f"Bearer {api_key}"}
        data: dict[str, str] = {}
        if settings.effective_fish_asr_model:
            data["model"] = settings.effective_fish_asr_model
        files = {"file": ("speech.wav", wav_bytes, "audio/wav")}
        timeout = max(float(settings.tts_timeout_seconds), 10.0)
        last_error: Exception | None = None
        for attempt in range(2):
            try:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(
                        f"{base_url}/v1/asr",
                        headers=headers,
                        data=data,
                        files=files,
                    )
                response.raise_for_status()
                return self._extract_text(response)
            except Exception as exc:
                last_error = exc
                if attempt == 0:
                    await asyncio.sleep(0.2)
        raise last_error or RuntimeError("Fish Audio ASR failed")

    def _extract_text(self, response: httpx.Response) -> str:
        content_type = response.headers.get("content-type", "")
        if "application/json" not in content_type:
            return response.text.strip()
        payload: Any = response.json()
        if isinstance(payload, dict):
            for key in ("text", "transcript", "result"):
                value = payload.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
            if isinstance(payload.get("segments"), list):
                return " ".join(
                    str(item.get("text") or "").strip()
                    for item in payload["segments"]
                    if isinstance(item, dict) and str(item.get("text") or "").strip()
                ).strip()
        return ""

"""Streaming STT provider abstraction."""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from ..config import Settings


@runtime_checkable
class StreamingSTT(Protocol):
    async def feed_audio(self, pcm: bytes) -> str | None:
        """Feed PCM bytes; return partial transcript text if changed, else None."""
        ...

    async def on_speech_start(self) -> None:
        ...

    async def on_speech_end(self) -> str:
        """Return final transcript."""
        ...

    def consume_metrics(self) -> dict[str, int]:
        """Return per-turn STT timing metrics (e.g. stt_partial_ms)."""
        ...

    def reset(self) -> None:
        ...


def get_streaming_stt(settings: Settings) -> StreamingSTT:
    provider = (settings.stt_provider or "whisper_stream").lower()
    if provider == "whisper_stream":
        from .whisper_streaming_stt import WhisperStreamingSTT

        return WhisperStreamingSTT(settings)
    raise ValueError(f"Unknown stt_provider: {provider}")

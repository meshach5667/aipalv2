"""Live Voice v2 streaming turn pipeline."""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from typing import AsyncIterator
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from ..models import User
from ..safety import crisis_reply, is_crisis_likely
from ..services.companion_orchestrator import preload_turn_context, run_turn_stream as run_companion_turn_stream

log = logging.getLogger("aipal.voice_turn")


def _session_uuid(session_id: str) -> uuid.UUID:
    try:
        return uuid.UUID(session_id)
    except ValueError:
        return uuid.uuid5(uuid.NAMESPACE_URL, f"aipal:voice-session:{session_id}")


async def run_voice_turn_stream(
    db: AsyncSession,
    user: User,
    text: str,
    session_id: str,
    *,
    cancel_event: asyncio.Event | None = None,
    preloaded_context: dict[str, Any] | None = None,
) -> AsyncIterator[dict[str, Any]]:
    """Yield streaming Brain events for live voice."""
    t0 = time.monotonic()
    sid = session_id or str(uuid.uuid4())

    if is_crisis_likely(text):
        reply = crisis_reply()
        yield {"type": "reply_delta", "text": reply}
        yield {
            "type": "turn_meta",
            "reply": reply,
            "crisis": True,
            "tool_actions": [],
            "plan_draft": None,
            "draft_confirmed": False,
            "mode": "companion",
            "emotion": {"emotion": "neutral", "intensity": 1, "context": "Crisis-safe reply."},
            "memories_used": [],
            "suggested_actions": [],
            "requires_confirmation": False,
            "confirmation_prompt": None,
            "conversation_id": sid,
            "metrics": {"turn_total_ms": int((time.monotonic() - t0) * 1000)},
        }
        return

    async for event in run_companion_turn_stream(
        db,
        user,
        text,
        conversation_id=_session_uuid(sid),
        source="voice",
        preloaded_context=preloaded_context,
    ):
        if cancel_event and cancel_event.is_set():
            return
        metrics = dict(event.get("metrics") or {})
        if event.get("type") == "reply_delta" and "first_token_ms" in metrics:
            metrics.setdefault("first_reply_delta_ms", metrics["first_token_ms"])
        if event.get("type") == "turn_complete":
            metrics["turn_total_ms"] = int((time.monotonic() - t0) * 1000)
        yield {**event, "metrics": metrics}


async def preload_voice_context(
    db: AsyncSession,
    user: User,
    session_id: str,
    *,
    partial_message: str = "",
    speech_start_started_at: float | None = None,
) -> dict[str, Any]:
    started = speech_start_started_at or time.monotonic()
    payload = await preload_turn_context(
        db,
        user,
        conversation_id=_session_uuid(session_id),
        partial_message=partial_message,
    )
    payload["speech_start_to_context_ready_ms"] = int((time.monotonic() - started) * 1000)
    return payload

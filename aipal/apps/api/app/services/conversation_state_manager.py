from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from .context_cache import get_context_cache, set_context_cache


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


async def get_voice_session_state(user_id: str, session_id: str) -> dict[str, Any]:
    cached = await get_context_cache(user_id, f"voice-state:{session_id}")
    return cached or {}


async def update_voice_session_state(user_id: str, session_id: str, **updates: Any) -> dict[str, Any]:
    state = await get_voice_session_state(user_id, session_id)
    state.update({key: value for key, value in updates.items() if value is not None})
    state["updated_at"] = _now_iso()
    await set_context_cache(user_id, f"voice-state:{session_id}", state)
    return state


async def mark_user_speaking(user_id: str, session_id: str, *, turn_id: str | None = None) -> dict[str, Any]:
    return await update_voice_session_state(
        user_id,
        session_id,
        last_speaker="user",
        currently_speaking="user",
        current_turn_id=turn_id,
        speech_started_at=_now_iso(),
    )


async def mark_ai_speaking(user_id: str, session_id: str, *, turn_id: str | None = None) -> dict[str, Any]:
    return await update_voice_session_state(
        user_id,
        session_id,
        last_speaker="aipal",
        currently_speaking="aipal",
        current_turn_id=turn_id,
    )


async def mark_listening(user_id: str, session_id: str) -> dict[str, Any]:
    return await update_voice_session_state(
        user_id,
        session_id,
        currently_speaking="none",
        last_state="listening",
    )

import asyncio
import base64
import json
import logging
import os
import tempfile
import time
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth import get_current_user
from ..config import get_settings
from ..db import get_db
from ..models import User
from ..safety import crisis_reply, is_crisis_likely
from ..schemas import (
    AudioTurnResponse,
    ConversationSessionSummary,
    ConversationTurnResponse,
    EmotionResponse,
    MemoryUsageResponse,
    PlanDraftResponse,
    SuggestedActionResponse,
    TextTurnRequest,
    TextTurnResponse,
    TtsRequest,
    TtsResponse,
    TtsVoiceOption,
)
from ..services.companion_orchestrator import run_turn as run_companion_turn
from ..services import conversation as conv_svc
from ..services.proactive_conversation_service import get_or_create_preferences
from ..stt import transcribe_path
from ..tts import synthesize, voice_options
from ..rate_limit import rate_limit_dependency

router = APIRouter(tags=["turn"], dependencies=[Depends(rate_limit_dependency("turn", limit=60))])
log = logging.getLogger("aipal.turn")
DEBUG_LOG = "/home/dev/.cursor/debug-60ce92.log"


def _session_uuid(session_id: str) -> uuid.UUID:
    try:
        return uuid.UUID(session_id)
    except ValueError:
        return uuid.uuid5(uuid.NAMESPACE_URL, f"aipal:audio-session:{session_id}")


def _agent_debug(hypothesis_id: str, location: str, message: str, data: dict, run_id: str = "pre-fix") -> None:
    try:
        entry = {
            "sessionId": "60ce92",
            "hypothesisId": hypothesis_id,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": int(time.time() * 1000),
            "runId": run_id,
        }
        with open(DEBUG_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        log.info("AGENT_DEBUG %s", json.dumps(entry))


async def _reply_for_text(
    db: AsyncSession,
    user: User,
    text: str,
    session_id: str | None = None,
) -> tuple[str, bool, list[str], str, PlanDraftResponse | None]:
    """Compatibility adapter for the legacy /turn/text response shape.

    All real companion reasoning now flows through CompanionOrchestrator so
    text, audio, companion, and websocket turns share the same response service.
    """
    if is_crisis_likely(text):
        sid = session_id or str(uuid.uuid4())
        return crisis_reply(), True, [], sid, None

    conversation_id = _session_uuid(session_id) if session_id else None
    result = await run_companion_turn(
        db,
        user,
        text,
        conversation_id=conversation_id,
        source="text",
    )
    tool_actions = [
        str(action.get("label") or action.get("type") or "")
        for action in result.get("suggested_actions", [])
        if isinstance(action, dict) and (action.get("label") or action.get("type"))
    ]
    response_session_id = session_id or (
        str(result["conversation_id"]) if result.get("conversation_id") else str(uuid.uuid4())
    )
    return (
        str(result["reply"]),
        False,
        tool_actions,
        response_session_id,
        result.get("plan_draft"),
    )


@router.get("/turn/sessions", response_model=list[ConversationSessionSummary])
@router.get("/sessions", response_model=list[ConversationSessionSummary])
async def list_sessions(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sessions = await conv_svc.list_sessions(db, user.id)
    return [ConversationSessionSummary(**s) for s in sessions]


@router.get("/turn/sessions/{session_id}", response_model=list[ConversationTurnResponse])
@router.get("/sessions/{session_id}", response_model=list[ConversationTurnResponse])
async def get_session_turns(
    session_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    turns = await conv_svc.get_session_turns(db, user.id, session_id)
    return [ConversationTurnResponse(**t) for t in turns]


@router.delete("/turn/sessions/{session_id}")
@router.delete("/sessions/{session_id}")
async def delete_session(
    session_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    deleted = await conv_svc.delete_session(db, user.id, session_id)
    return {"ok": True, "deleted": deleted}


@router.post("/turn/text", response_model=TextTurnResponse)
async def text_turn(
    body: TextTurnRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    reply, crisis, tool_actions, sid, draft = await _reply_for_text(db, user, body.text, body.session_id)
    preferences = await get_or_create_preferences(db, user.id)
    return TextTurnResponse(
        reply=reply,
        assistantMessage=reply,
        speak=False,
        voiceId=preferences.tts_voice,
        uiState="idle",
        crisis=crisis,
        tool_actions=tool_actions,
        session_id=sid,
        plan_draft=draft,
    )


@router.post("/turn/audio", response_model=AudioTurnResponse)
async def audio_turn(
    file: UploadFile = File(...),
    session_id: str | None = Form(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    turn_t0 = time.monotonic()
    raw = await file.read()
    _agent_debug("A", "turn.py:audio_turn", "audio_upload_received", {"bytes": len(raw), "user_id": str(user.id)})
    if not raw:
        return AudioTurnResponse(
            transcript="",
            reply="I did not receive any audio. Stay in Live mode and speak naturally.",
            assistantMessage="I did not receive any audio. Stay in Live mode and speak naturally.",
            speak=False,
            uiState="listening",
            session_id=session_id,
        )

    suffix = Path(file.filename or "turn.m4a").suffix.lower() or ".m4a"
    fd, tmp_path = tempfile.mkstemp(suffix=suffix, prefix="aipal-v2-")
    os.close(fd)
    try:
        Path(tmp_path).write_bytes(raw)
        try:
            stt_t0 = time.monotonic()
            transcript = await asyncio.to_thread(transcribe_path, tmp_path)
            stt_ms = int((time.monotonic() - stt_t0) * 1000)
        except Exception:
            log.exception("Audio transcription failed")
            return AudioTurnResponse(
                transcript="",
                reply="I could not read that audio clearly. Try one short sentence near the microphone.",
                assistantMessage="I could not read that audio clearly. Try one short sentence near the microphone.",
                speak=False,
                uiState="listening",
                session_id=session_id,
            )
    finally:
        Path(tmp_path).unlink(missing_ok=True)

    if not (transcript or "").strip():
        return AudioTurnResponse(
            transcript="",
            reply="I did not catch that clearly. Try one short sentence near the microphone.",
            assistantMessage="I did not catch that clearly. Try one short sentence near the microphone.",
            speak=False,
            uiState="listening",
            session_id=session_id,
        )
    transcript_text = transcript.strip()
    words = transcript_text.split()
    short_greetings = {"hi", "hey", "hello", "yo", "aipal", "pal"}
    if len(words) <= 1 and transcript_text.lower().strip(".,!?") not in short_greetings:
        return AudioTurnResponse(
            transcript=transcript_text,
            reply=f"I only caught “{transcript_text}”. Say the full thought again and I’ll listen before I respond.",
            assistantMessage=f"I only caught “{transcript_text}”. Say the full thought again and I’ll listen before I respond.",
            speak=False,
            uiState="listening",
            crisis=False,
            tool_actions=[],
            session_id=session_id,
        )

    try:
        llm_t0 = time.monotonic()
        result = await run_companion_turn(
            db,
            user,
            transcript_text,
            conversation_id=_session_uuid(session_id) if session_id else None,
            source="voice",
        )
        llm_ms = int((time.monotonic() - llm_t0) * 1000)
    except Exception:
        await db.rollback()
        log.exception("Audio companion turn failed")
        return AudioTurnResponse(
            transcript=transcript_text,
            reply="I heard you, but I had trouble thinking through that voice turn. Try saying it once more, or type it and I will pick it up from there.",
            assistantMessage="I heard you, but I had trouble thinking through that voice turn. Try saying it once more, or type it and I will pick it up from there.",
            speak=False,
            uiState="listening",
            crisis=False,
            tool_actions=[],
            session_id=session_id,
        )
    reply = str(result["reply"])
    try:
        tts_t0 = time.monotonic()
        preferences = await get_or_create_preferences(db, user.id)
        audio_bytes, audio_mime = await synthesize(reply, voice=preferences.tts_voice)
        tts_ms = int((time.monotonic() - tts_t0) * 1000)
    except Exception:
        log.exception("Audio TTS synthesis failed")
        audio_bytes, audio_mime = b"", None
        tts_ms = 0
    log.info(
        "audio_turn timing user=%s bytes=%d stt_ms=%d llm_ms=%d tts_ms=%d total_ms=%d transcript_len=%d reply_len=%d",
        user.id,
        len(raw),
        stt_ms,
        llm_ms,
        tts_ms,
        int((time.monotonic() - turn_t0) * 1000),
        len(transcript_text),
        len(reply),
    )
    return AudioTurnResponse(
        transcript=transcript_text,
        reply=reply,
        assistantMessage=reply,
        speak=bool(audio_bytes),
        voiceId=preferences.tts_voice,
        uiState="speaking" if audio_bytes else "idle",
        crisis=False,
        tool_actions=[],
        plan_draft=result["plan_draft"],
        draft_confirmed=False,
        session_id=str(result["conversation_id"]) if result.get("conversation_id") else session_id,
        audio_base64=base64.b64encode(audio_bytes).decode("ascii") if audio_bytes else None,
        audio_mime=audio_mime if audio_bytes else None,
        mode=str(result["mode"]),
        emotion=EmotionResponse(**result["emotion"]),
        memories_used=[MemoryUsageResponse(**m) for m in result["memories_used"]],
        suggested_actions=[SuggestedActionResponse(**a) for a in result["suggested_actions"]],
        requires_confirmation=bool(result["requires_confirmation"]),
        confirmation_prompt=result["confirmation_prompt"],
        conversation_id=result["conversation_id"],
    )


@router.post("/turn/tts", response_model=TtsResponse)
async def tts_turn(
    body: TtsRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    text = (body.text or "").strip()
    if not text:
        return TtsResponse(text="", speak=False, uiState="idle")
    preferences = await get_or_create_preferences(db, user.id)
    voice = body.voice or preferences.tts_voice
    audio_bytes, audio_mime = await synthesize(text, voice=voice)
    return TtsResponse(
        text=text,
        assistantMessage=text,
        speak=bool(audio_bytes),
        voiceId=voice,
        uiState="speaking" if audio_bytes else "idle",
        audio_base64=base64.b64encode(audio_bytes).decode("ascii") if audio_bytes else None,
        audio_mime=audio_mime if audio_bytes else None,
    )


@router.get("/turn/tts/voices", response_model=list[TtsVoiceOption])
async def list_tts_voices(
    user: User = Depends(get_current_user),
):
    return [TtsVoiceOption(**voice) for voice in voice_options()]


@router.get("/voice/profiles")
async def list_voice_profiles(
    user: User = Depends(get_current_user),
):
    return {"profiles": voice_options(), "default": "default"}


@router.get("/voice/capabilities")
async def voice_capabilities(
    user: User = Depends(get_current_user),
):
    settings = get_settings()
    tts_provider = settings.effective_tts_provider
    stt_provider = settings.effective_stt_provider
    realtime_provider = (settings.realtime_voice_provider or "").strip()
    return {
        "transport": settings.live_voice_transport,
        "live_voice_v2": settings.live_voice_v2,
        "stt": {
            "provider": stt_provider,
            "configured": (
                bool(settings.effective_fish_api_key)
                if stt_provider == "fish_audio"
                else True
            ),
            "model": settings.whisper_model
            if stt_provider == "whisper_stream"
            else settings.effective_fish_asr_model,
            "beam_size": settings.whisper_beam_size if stt_provider == "whisper_stream" else None,
            "partial_interval_ms": settings.whisper_stream_partial_interval_ms
            if stt_provider == "whisper_stream"
            else None,
            "confidence_gate": {
                "min_confidence": settings.stt_min_confidence,
                "max_no_speech_probability": settings.stt_max_no_speech_probability,
                "min_final_chars": settings.stt_min_final_chars,
            },
            "streaming_partials": settings.live_voice_v2 and stt_provider == "whisper_stream",
            "automatic_language_detection": True,
        },
        "tts": {
            "provider": tts_provider,
            "configured": (
                bool(settings.effective_fish_api_key)
                if tts_provider == "fish"
                else True
            ),
            "model": settings.effective_fish_tts_model if tts_provider == "fish" else None,
            "streaming": True,
            "distinct_voice_profiles": tts_provider in {"edge", "fish", "say"},
            "fallback_safe": True,
        },
        "barge_in": {
            "client_vad": True,
            "echo_cancellation_requested": True,
            "noise_suppression_requested": True,
            "auto_gain_control_requested": True,
        },
        "realtime_ready": {
            "enabled": bool(realtime_provider),
            "provider": realtime_provider or None,
            "note": (
                "Dedicated realtime provider configured."
                if realtime_provider
                else "Using WebSocket PCM with streaming STT/TTS fallback."
            ),
        },
    }

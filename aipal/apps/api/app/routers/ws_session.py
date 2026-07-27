import asyncio
import base64
import json
import logging
import time
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import JWTError, jwt
from sqlalchemy import select

from ..config import get_settings
from ..db import async_session
from ..models import Conversation, LiveSession, User
from ..safety import crisis_reply, is_crisis_likely
from ..services.stt_provider import get_streaming_stt
from ..services.voice_turn import preload_voice_context, run_voice_turn_stream
from ..services.conversation_manager import conversation_manager, ConversationManagerResult
from ..services.conversation_state_manager import mark_ai_speaking, mark_listening, mark_user_speaking, update_voice_session_state
from ..tts import synthesize_stream
from ..voice_pipeline import TurnCancellationRegistry, TurnRateLimiter, split_sentences

router = APIRouter()
log = logging.getLogger("aipal.ws")
settings = get_settings()

_rate_limiter = TurnRateLimiter(settings.live_turns_per_minute)


async def _user_from_token(token: str) -> User | None:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        user_id = uuid.UUID(payload["sub"])
    except (JWTError, ValueError):
        return None
    async with async_session() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()


async def _send_state(websocket: WebSocket, state: str) -> None:
    await websocket.send_json({"type": "state", "state": state})


def _stt_is_reliable(transcript: str, metrics: dict[str, int | float]) -> bool:
    if len(transcript.strip()) < settings.stt_min_final_chars:
        return False
    confidence = float(metrics.get("stt_confidence", 1.0) or 0.0)
    no_speech = float(metrics.get("stt_no_speech_probability", 0.0) or 0.0)
    if confidence < settings.stt_min_confidence:
        return False
    return no_speech <= settings.stt_max_no_speech_probability


async def _voice_profile_from_preload(preload_task: asyncio.Task | None) -> str:
    voice_profile = "calm_female"
    if preload_task is None:
        return voice_profile
    try:
        preloaded_context = await preload_task
        user_preferences = (preloaded_context or {}).get("user_preferences") or {}
        return str(user_preferences.get("voice_profile") or user_preferences.get("tts_voice") or voice_profile)
    except Exception:
        log.exception("voice_profile_preload_failed")
        return voice_profile


async def _send_direct_voice_reply(
    websocket: WebSocket,
    turn_id: str,
    *,
    voice_profile: str,
    result: ConversationManagerResult,
) -> None:
    reply = result.reply or "Sorry, I didn't catch that clearly. Could you say it again?"
    metrics = dict(result.metrics or {})
    await websocket.send_json({"type": "reply_delta", "turn_id": turn_id, "text": reply})
    await websocket.send_json({"type": "sentence_ready", "turn_id": turn_id, "text": reply})
    chunk_index = 0
    async for audio, mime in synthesize_stream(reply, voice=voice_profile):
        if not audio:
            continue
        payload = {
            "turn_id": turn_id,
            "chunk_index": chunk_index,
            "is_final": False,
            "text": reply,
            "data": base64.b64encode(audio).decode("ascii"),
            "mime": mime,
        }
        chunk_index += 1
        await websocket.send_json({"type": "tts_chunk", **payload})
        await websocket.send_json({"type": "audio_chunk", **payload})
    await websocket.send_json(
        {"type": "tts_complete", "turn_id": turn_id, "chunk_index": chunk_index, "is_final": True}
    )
    complete_payload = {
        "type": "turn_complete",
        "turn_id": turn_id,
        "reply": reply,
        "assistantMessage": reply,
        "speak": True,
        "voiceId": voice_profile,
        "uiState": "speaking",
        "action": None,
        "todaySync": None,
        "tool_actions": [],
        "draft_confirmed": result.draft_confirmed,
        "mode": "assistant" if result.intent != "general_conversation" else "companion",
        "emotion": {"emotion": "neutral", "intensity": 1, "context": f"Conversation Manager: {result.intent}."},
        "memories_used": [],
        "suggested_actions": result.suggested_actions or [],
        "requires_confirmation": result.requires_confirmation,
        "confirmation_prompt": result.confirmation_prompt,
        "metrics": {
            **metrics,
            "stt_reliable": 0 if result.intent == "low_confidence_transcript" else 1,
        },
    }
    if result.plan_draft:
        complete_payload["plan_draft"] = result.plan_draft
    await websocket.send_json(complete_payload)
    await _send_state(websocket, "listening")


async def _preload_context_for_turn(user: User, session_id: uuid.UUID, turn_id: str, started_at: float) -> dict:
    async with async_session() as db:
        return await preload_voice_context(
            db,
            user,
            str(session_id),
            partial_message="",
            speech_start_started_at=started_at,
        )


async def _run_turn_pipeline(
    websocket: WebSocket,
    user: User,
    session_id: uuid.UUID,
    turn_id: str,
    text: str,
    cancel_registry: TurnCancellationRegistry,
    *,
    stt_final_ms: int | None = None,
    stt_metrics: dict[str, int] | None = None,
    preload_task: asyncio.Task | None = None,
) -> None:
    cancel_event = asyncio.Event()
    tts_t0: float | None = None
    reply_buffer = ""
    metrics: dict[str, int] = {}
    chunk_index = 0
    if stt_final_ms is not None:
        metrics["stt_final_ms"] = stt_final_ms
    if stt_metrics:
        metrics.update(stt_metrics)

    async def _pipeline() -> None:
        nonlocal reply_buffer, tts_t0, metrics, chunk_index
        try:
            preloaded_context = None
            voice_profile = "calm_female"
            if preload_task is not None:
                try:
                    preloaded_context = await preload_task
                    user_preferences = (preloaded_context or {}).get("user_preferences") or {}
                    voice_profile = str(user_preferences.get("voice_profile") or user_preferences.get("tts_voice") or voice_profile)
                except Exception:
                    log.exception("voice_context_preload_failed turn=%s", turn_id)
            async with async_session() as db:
                async def _speak_sentence(sentence: str) -> None:
                    nonlocal tts_t0, metrics, chunk_index
                    if cancel_event.is_set():
                        return
                    await websocket.send_json(
                        {"type": "sentence_ready", "turn_id": turn_id, "text": sentence}
                    )
                    sentence_started = time.monotonic()
                    async for audio, mime in synthesize_stream(sentence, voice=voice_profile):
                        if cancel_event.is_set():
                            return
                        if audio:
                            if tts_t0 is None:
                                tts_t0 = time.monotonic()
                                metrics["first_tts_chunk_ms"] = int((tts_t0 - sentence_started) * 1000)
                                await mark_ai_speaking(str(user.id), str(session_id), turn_id=turn_id)
                            payload = {
                                "turn_id": turn_id,
                                "chunk_index": chunk_index,
                                "is_final": False,
                                "text": sentence,
                                "data": base64.b64encode(audio).decode("ascii"),
                                "mime": mime,
                            }
                            chunk_index += 1
                            await websocket.send_json({"type": "tts_chunk", **payload})
                            await websocket.send_json({"type": "audio_chunk", **payload})

                async for event in run_voice_turn_stream(
                    db,
                    user,
                    text,
                    str(session_id),
                    cancel_event=cancel_event,
                    preloaded_context=preloaded_context,
                ):
                    if cancel_event.is_set():
                        return
                    etype = event.get("type")
                    if etype == "context_ready":
                        metrics.update(event.get("metrics") or {})
                        voice_profile = str(event.get("voice_profile") or voice_profile)
                        await websocket.send_json(
                            {
                                "type": "context_ready",
                                "turn_id": turn_id,
                                "mode": event.get("mode"),
                                "emotion": event.get("emotion"),
                                "metrics": metrics,
                                "voice_profile": voice_profile,
                            }
                        )
                    elif etype == "reply_delta":
                        metrics.update(event.get("metrics") or {})
                        chunk = event.get("text", "")
                        if chunk:
                            await websocket.send_json(
                                {"type": "reply_delta", "turn_id": turn_id, "text": chunk}
                            )
                            reply_buffer += chunk
                    elif etype == "sentence_ready":
                        sentence = str(event.get("text") or "").strip()
                        if sentence:
                            if sentence in reply_buffer:
                                reply_buffer = reply_buffer.replace(sentence, "", 1).strip()
                            await _speak_sentence(sentence)
                    elif etype in {"post_processing_started", "tool_suggestion", "memory_suggestion"}:
                        await websocket.send_json({"turn_id": turn_id, **event})
                    elif etype in {"turn_meta", "turn_complete"}:
                        metrics.update(event.get("metrics") or {})
                        if reply_buffer.strip() and not cancel_event.is_set():
                            await _speak_sentence(reply_buffer.strip())
                            reply_buffer = ""
                        await websocket.send_json(
                            {
                                "type": "tts_complete",
                                "turn_id": turn_id,
                                "chunk_index": chunk_index,
                                "is_final": True,
                            }
                        )
                        payload = {
                            "type": "turn_complete",
                            "turn_id": turn_id,
                            "reply": event.get("reply", ""),
                            "assistantMessage": event.get("reply", ""),
                            "speak": True,
                            "voiceId": voice_profile,
                            "uiState": "speaking",
                            "action": event.get("tool_actions", []),
                            "todaySync": None,
                            "tool_actions": event.get("tool_actions", []),
                            "draft_confirmed": event.get("draft_confirmed", False),
                            "mode": event.get("mode"),
                            "emotion": event.get("emotion"),
                            "memories_used": event.get("memories_used", []),
                            "suggested_actions": event.get("suggested_actions", []),
                            "requires_confirmation": event.get("requires_confirmation", False),
                            "confirmation_prompt": event.get("confirmation_prompt"),
                            "conversation_id": event.get("conversation_id"),
                            "metrics": metrics,
                        }
                        draft = event.get("plan_draft")
                        if draft:
                            payload["plan_draft"] = (
                                draft.model_dump() if hasattr(draft, "model_dump") else draft
                            )
                        log.info(
                            "live_voice turn_complete user=%s session=%s turn=%s reply_len=%d metrics=%s",
                            user.id,
                            session_id,
                            turn_id,
                            len(event.get("reply", "") or ""),
                            metrics,
                        )
                        await websocket.send_json(payload)
                        await mark_listening(str(user.id), str(session_id))
                        await _send_state(websocket, "listening")
        except asyncio.CancelledError:
            await websocket.send_json({"type": "turn_cancelled", "turn_id": turn_id})
            await _send_state(websocket, "listening")
            raise
        except Exception:
            log.exception("live_turn_pipeline_failed turn=%s", turn_id)
            raise

    task = asyncio.create_task(_pipeline())
    cancel_registry.register(turn_id, task)
    try:
        await task
    except asyncio.CancelledError:
        cancel_event.set()
    finally:
        cancel_registry.clear(turn_id)


@router.websocket("/ws/session")
async def live_session(websocket: WebSocket):
    await websocket.accept()
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4401)
        return
    user = await _user_from_token(token)
    if not user:
        await websocket.close(code=4401)
        return

    requested_session = websocket.query_params.get("session_id")
    try:
        session_id = uuid.UUID(requested_session) if requested_session else uuid.uuid4()
    except ValueError:
        session_id = uuid.uuid4()
    async with async_session() as db:
        existing_live = await db.get(LiveSession, session_id)
        if existing_live is None:
            db.add(LiveSession(id=session_id, user_id=user.id, state="active"))
        else:
            existing_live.state = "active"
            existing_live.ended_at = None
        existing_conv = await db.get(Conversation, session_id)
        if existing_conv is None:
            db.add(Conversation(id=session_id, user_id=user.id, mode="companion", title="Live session"))
        await db.commit()
    await update_voice_session_state(
        str(user.id),
        str(session_id),
        conversation_id=str(session_id),
        last_state="listening",
        conversation_mode="companion",
    )

    await websocket.send_json(
        {"type": "session_started", "session_id": str(session_id), "state": "live"}
    )
    await _send_state(websocket, "listening")
    log.info(
        "live_voice session_started user=%s email=%s session=%s",
        user.id,
        user.email,
        session_id,
    )

    stt = get_streaming_stt(settings) if settings.live_voice_v2 else None
    cancel_registry = TurnCancellationRegistry()
    inflight_tasks: set[asyncio.Task] = set()
    preload_tasks: dict[str, asyncio.Task] = {}

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type")

            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})
                continue
            if msg_type == "end":
                break

            if msg_type == "interrupt":
                turn_id = msg.get("turn_id") or ""
                await conversation_manager.handle_interrupt(
                    user_id=user.id,
                    session_id=session_id,
                    turn_id=None if turn_id in {"", "all", "*"} else str(turn_id),
                )
                if turn_id in {"", "all", "*"}:
                    cancelled_count = cancel_registry.cancel_all()
                    if cancelled_count:
                        await mark_user_speaking(str(user.id), str(session_id), turn_id=None)
                        await websocket.send_json(
                            {
                                "type": "turn_cancelled",
                                "turn_id": "all",
                                "cancelled_count": cancelled_count,
                            }
                        )
                        await _send_state(websocket, "listening")
                    continue
                if cancel_registry.cancel(turn_id):
                    await mark_user_speaking(str(user.id), str(session_id), turn_id=turn_id)
                    await websocket.send_json({"type": "turn_cancelled", "turn_id": turn_id})
                    await _send_state(websocket, "listening")
                continue

            if not settings.live_voice_v2:
                if msg_type == "text_turn":
                    text = (msg.get("text") or "").strip()
                    if not text:
                        continue
                    await _send_state(websocket, "thinking")
                    if is_crisis_likely(text):
                        await websocket.send_json(
                            {
                                "type": "reply",
                                "text": crisis_reply(),
                                "crisis": True,
                                "state": "speaking",
                            }
                        )
                        continue
                    turn_id = msg.get("turn_id") or str(uuid.uuid4())
                    await _run_turn_pipeline(
                        websocket,
                        user,
                        session_id,
                        turn_id,
                        text,
                        cancel_registry,
                    )
                elif msg_type == "audio_chunk":
                    await websocket.send_json(
                        {
                            "type": "transcript_partial",
                            "text": "",
                            "note": "Enable LIVE_VOICE_V2 for streaming STT",
                        }
                    )
                continue

            if msg_type == "audio_frame":
                if stt is None:
                    continue
                data_b64 = msg.get("data") or ""
                try:
                    pcm = base64.b64decode(data_b64)
                except Exception:
                    continue
                partial = await stt.feed_audio(pcm)
                turn_id = msg.get("turn_id") or ""
                if partial:
                    await conversation_manager.handle_partial_transcript(
                        user_id=user.id,
                        session_id=session_id,
                        turn_id=turn_id,
                        text=partial,
                        confidence=None,
                    )
                    await websocket.send_json(
                        {"type": "transcript_partial", "turn_id": turn_id, "text": partial}
                    )
                continue

            if msg_type == "speech_start":
                turn_id = msg.get("turn_id") or str(uuid.uuid4())
                cancelled_count = cancel_registry.cancel_all()
                if cancelled_count:
                    await websocket.send_json(
                        {
                            "type": "turn_cancelled",
                            "turn_id": "all",
                            "cancelled_count": cancelled_count,
                        }
                    )
                if stt:
                    await stt.on_speech_start()
                await mark_user_speaking(str(user.id), str(session_id), turn_id=turn_id)
                preload_tasks[turn_id] = asyncio.create_task(
                    _preload_context_for_turn(user, session_id, turn_id, time.monotonic())
                )
                log.info(
                    "live_voice speech_start user=%s session=%s turn=%s cancelled=%d",
                    user.id,
                    session_id,
                    turn_id,
                    cancelled_count,
                )
                continue

            turn_id = msg.get("turn_id") or str(uuid.uuid4())

            if msg_type == "speech_end":
                if not _rate_limiter.allow(str(user.id)):
                    await websocket.send_json(
                        {
                            "type": "error",
                            "turn_id": turn_id,
                            "message": "Rate limit exceeded; try again shortly.",
                        }
                    )
                    continue

                stt_t0 = time.monotonic()
                transcript = ""
                stt_metrics: dict[str, int] = {}
                if stt:
                    transcript = await stt.on_speech_end()
                    stt_metrics = stt.consume_metrics()
                stt_final_ms = int((time.monotonic() - stt_t0) * 1000)
                transcript = (transcript or "").strip()
                log.info(
                    "live_voice speech_end user=%s session=%s turn=%s stt_final_ms=%d transcript_len=%d empty=%s",
                    user.id,
                    session_id,
                    turn_id,
                    stt_final_ms,
                    len(transcript),
                    not transcript,
                )

                if not transcript:
                    await websocket.send_json(
                        {
                            "type": "transcript_final",
                            "turn_id": turn_id,
                            "text": "",
                            "confidence": 0.0,
                        }
                    )
                    continue

                log.info(
                    "live_voice transcript user=%s session=%s turn=%s text=%r",
                    user.id,
                    session_id,
                    turn_id,
                    transcript[:200],
                )
                await websocket.send_json(
                    {
                        "type": "transcript_final",
                        "turn_id": turn_id,
                        "text": transcript,
                        "confidence": stt_metrics.get("stt_confidence"),
                    }
                )
                async with async_session() as db:
                    manager_result = await conversation_manager.handle_final_transcript(
                        db,
                        user,
                        session_id=session_id,
                        turn_id=turn_id,
                        transcript=transcript,
                        confidence=stt_metrics.get("stt_confidence"),
                        language=stt_metrics.get("stt_language"),
                        metrics={**stt_metrics, "stt_final_ms": stt_final_ms},
                    )
                if manager_result.action == "direct_reply":
                    preload_task = preload_tasks.pop(turn_id, None)
                    voice_profile = await _voice_profile_from_preload(preload_task)
                    await _send_state(websocket, "speaking")
                    await _send_direct_voice_reply(
                        websocket,
                        turn_id,
                        voice_profile=voice_profile,
                        result=manager_result,
                    )
                    continue
                await _send_state(websocket, "thinking")
                await _send_state(websocket, "speaking")
                task = asyncio.create_task(
                    _run_turn_pipeline(
                        websocket,
                        user,
                        session_id,
                        turn_id,
                        manager_result.transcript,
                        cancel_registry,
                        stt_final_ms=stt_final_ms,
                        stt_metrics=stt_metrics,
                        preload_task=preload_tasks.pop(turn_id, None),
                    )
                )
                inflight_tasks.add(task)
                task.add_done_callback(inflight_tasks.discard)
                continue

            if msg_type == "text_turn":
                text = (msg.get("text") or "").strip()
                if not text:
                    continue
                if not _rate_limiter.allow(str(user.id)):
                    await websocket.send_json(
                        {
                            "type": "error",
                            "turn_id": turn_id,
                            "message": "Rate limit exceeded; try again shortly.",
                        }
                    )
                    continue
                await _send_state(websocket, "thinking")
                await _send_state(websocket, "speaking")
                task = asyncio.create_task(
                    _run_turn_pipeline(websocket, user, session_id, turn_id, text, cancel_registry)
                )
                inflight_tasks.add(task)
                task.add_done_callback(inflight_tasks.discard)

    except WebSocketDisconnect:
        log.info("live_voice disconnected user=%s session=%s", user.id, session_id)
    finally:
        cancel_registry.cancel_all()
        for task in list(inflight_tasks):
            task.cancel()
        for task in list(preload_tasks.values()):
            task.cancel()
        if inflight_tasks:
            await asyncio.gather(*inflight_tasks, return_exceptions=True)
        if preload_tasks:
            await asyncio.gather(*preload_tasks.values(), return_exceptions=True)
        async with async_session() as db:
            result = await db.execute(select(LiveSession).where(LiveSession.id == session_id))
            live = result.scalar_one_or_none()
            if live:
                live.state = "ended"
                live.ended_at = datetime.now(UTC)
                await db.commit()
        try:
            await websocket.send_json({"type": "session_ended", "state": "resting"})
        except Exception:
            pass

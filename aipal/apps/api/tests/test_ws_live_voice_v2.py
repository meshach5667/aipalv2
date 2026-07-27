"""WebSocket integration tests for Live Voice v2."""

import asyncio
import json
import uuid
from contextlib import contextmanager
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from starlette.testclient import TestClient

from app.auth import create_access_token
from app.main import app
from app.services.conversation_state_manager import get_voice_session_state


def _make_user(user_id: uuid.UUID):
    user = MagicMock()
    user.id = user_id
    user.email = "ws-test@example.com"
    return user


@contextmanager
def _mock_ws_db():
    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = MagicMock()
    db.execute = AsyncMock(return_value=result)
    db.add = MagicMock()
    db.commit = AsyncMock()
    cm = AsyncMock()
    cm.__aenter__.return_value = db
    cm.__aexit__.return_value = None
    with patch("app.routers.ws_session.async_session", return_value=cm):
        yield


async def _fake_voice_stream(*_args, **_kwargs):
    yield {"type": "context_ready", "metrics": {"context_items_count": 1}}
    yield {"type": "reply_delta", "text": "Hi there."}
    yield {"type": "sentence_ready", "text": "Hi there."}
    yield {
        "type": "turn_complete",
        "reply": "Hi there.",
        "tool_actions": [],
        "draft_confirmed": False,
        "metrics": {"llm_ttft_ms": 10},
    }


async def _fake_tts_stream(_text, voice=None):
    yield b"audio-bytes", "audio/mpeg"


def _recv_until(ws, target_type: str, *, max_messages: int = 30):
    for _ in range(max_messages):
        msg = json.loads(ws.receive_text())
        if msg.get("type") == target_type:
            return msg
        if msg.get("type") == "error":
            pytest.fail(msg.get("message"))
    pytest.fail(f"Did not receive {target_type}")


def test_ws_speech_end_turn_complete():
    user_id = uuid.uuid4()
    token = create_access_token(user_id, "ws-test@example.com")
    user = _make_user(user_id)

    mock_stt = MagicMock()
    mock_stt.on_speech_start = AsyncMock()
    mock_stt.on_speech_end = AsyncMock(return_value="hello there")
    mock_stt.consume_metrics = MagicMock(return_value={"stt_partial_ms": 42})
    mock_stt.feed_audio = AsyncMock(return_value=None)

    with (
        _mock_ws_db(),
        patch("app.routers.ws_session._user_from_token", new_callable=AsyncMock, return_value=user),
        patch("app.routers.ws_session.get_streaming_stt", return_value=mock_stt),
        patch("app.routers.ws_session.run_voice_turn_stream", new=_fake_voice_stream),
        patch("app.routers.ws_session.synthesize_stream", side_effect=_fake_tts_stream),
        patch("app.routers.ws_session._rate_limiter") as mock_rl,
    ):
        mock_rl.allow.return_value = True
        with TestClient(app) as client:
            with client.websocket_connect(f"/api/v2/ws/session?token={token}") as ws:
                started = json.loads(ws.receive_text())
                assert started["type"] == "session_started"

                turn_id = "turn-1"
                ws.send_text(json.dumps({"type": "speech_start", "turn_id": turn_id}))
                ws.send_text(json.dumps({"type": "speech_end", "turn_id": turn_id}))

                audio_chunks = []
                turn_complete = None
                for _ in range(30):
                    msg = json.loads(ws.receive_text())
                    if msg.get("type") == "audio_chunk":
                        audio_chunks.append(msg)
                    if msg.get("type") == "turn_complete":
                        turn_complete = msg
                        break
                    if msg.get("type") == "error":
                        pytest.fail(msg.get("message"))

                assert turn_complete is not None
                assert turn_complete["reply"] == "Hi there."
                assert turn_complete["metrics"].get("stt_partial_ms") == 42
                assert "stt_final_ms" in turn_complete["metrics"]
                assert "llm_ttft_ms" in turn_complete["metrics"]
                assert len(audio_chunks) >= 1
                ws.send_text(json.dumps({"type": "end"}))

    state = asyncio.run(get_voice_session_state(str(user_id), str(uuid.UUID(started["session_id"]))))
    assert state.get("conversation_id") == started["session_id"]


async def _slow_voice_stream(*_args, cancel_event=None, **_kwargs):
    yield {"type": "reply_delta", "text": "Still working..."}
    while cancel_event is None or not cancel_event.is_set():
        await asyncio.sleep(0.02)


def test_ws_interrupt_cancels_turn():
    user_id = uuid.uuid4()
    token = create_access_token(user_id, "ws-test@example.com")
    user = _make_user(user_id)

    with (
        _mock_ws_db(),
        patch("app.routers.ws_session._user_from_token", new_callable=AsyncMock, return_value=user),
        patch("app.routers.ws_session.run_voice_turn_stream", new=_slow_voice_stream),
        patch("app.routers.ws_session.synthesize_stream", side_effect=_fake_tts_stream),
        patch("app.routers.ws_session._rate_limiter") as mock_rl,
    ):
        mock_rl.allow.return_value = True
        with TestClient(app) as client:
            with client.websocket_connect(f"/api/v2/ws/session?token={token}") as ws:
                json.loads(ws.receive_text())  # session_started

                turn_id = "turn-interrupt"
                ws.send_text(json.dumps({"type": "text_turn", "text": "interrupt me", "turn_id": turn_id}))
                _recv_until(ws, "reply_delta")

                ws.send_text(json.dumps({"type": "interrupt", "turn_id": turn_id}))
                cancelled = _recv_until(ws, "turn_cancelled")
                assert cancelled["turn_id"] == turn_id
                ws.send_text(json.dumps({"type": "end"}))


async def _sentence_before_complete_stream(*_args, **_kwargs):
    yield {"type": "context_ready", "metrics": {"context_items_count": 1}}
    yield {"type": "reply_delta", "text": "First sentence."}
    yield {"type": "sentence_ready", "text": "First sentence."}
    await asyncio.sleep(0.02)
    yield {"type": "turn_complete", "reply": "First sentence.", "metrics": {"first_token_ms": 2}}


def test_ws_sentence_ready_starts_tts_before_turn_complete():
    user_id = uuid.uuid4()
    token = create_access_token(user_id, "ws-tts@example.com")
    user = _make_user(user_id)

    with (
        _mock_ws_db(),
        patch("app.routers.ws_session._user_from_token", new_callable=AsyncMock, return_value=user),
        patch("app.routers.ws_session.run_voice_turn_stream", new=_sentence_before_complete_stream),
        patch("app.routers.ws_session.synthesize_stream", side_effect=_fake_tts_stream),
        patch("app.routers.ws_session._rate_limiter") as mock_rl,
    ):
        mock_rl.allow.return_value = True
        with TestClient(app) as client:
            with client.websocket_connect(f"/api/v2/ws/session?token={token}") as ws:
                json.loads(ws.receive_text())
                ws.send_text(json.dumps({"type": "text_turn", "text": "hello", "turn_id": "tts-turn"}))
                saw_tts = False
                saw_complete = False
                for _ in range(30):
                    msg = json.loads(ws.receive_text())
                    if msg.get("type") == "tts_chunk":
                        saw_tts = True
                        assert msg["chunk_index"] == 0
                        assert msg["is_final"] is False
                    if msg.get("type") == "tts_complete":
                        saw_complete = True
                        assert msg["is_final"] is True
                    if msg.get("type") == "turn_complete":
                        assert saw_tts is True
                        assert saw_complete is True
                        break
                    if msg.get("type") == "error":
                        pytest.fail(msg.get("message"))
                else:
                    pytest.fail("Did not receive turn_complete")
                ws.send_text(json.dumps({"type": "end"}))


def test_ws_session_survives_reconnect_with_session_id():
    user_id = uuid.uuid4()
    token = create_access_token(user_id, "ws-reconnect@example.com")
    user = _make_user(user_id)
    session_id = uuid.uuid4()

    with (
        _mock_ws_db(),
        patch("app.routers.ws_session._user_from_token", new_callable=AsyncMock, return_value=user),
    ):
        with TestClient(app) as client:
            with client.websocket_connect(f"/api/v2/ws/session?token={token}&session_id={session_id}") as ws:
                started = json.loads(ws.receive_text())
                assert started["session_id"] == str(session_id)
                ws.send_text(json.dumps({"type": "end"}))

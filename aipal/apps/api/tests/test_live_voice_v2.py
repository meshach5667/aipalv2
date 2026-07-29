"""Live Voice v2 unit tests."""

import asyncio
import base64
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import numpy as np
import pytest

from app.voice_pipeline import TurnCancellationRegistry, split_sentences, strip_plan_json_block


def test_split_sentences():
    complete, rest = split_sentences("Hello there. How are")
    assert complete == ["Hello there."]
    assert rest == "How are"
    complete2, rest2 = split_sentences("Done.", flush=True)
    assert complete2 == ["Done."]
    assert rest2 == ""


def test_split_sentences_flushes_long_clause():
    complete, rest = split_sentences(
        "Okay I’ll put the proposal work after your morning meeting, then keep the evening lighter and leave room for rest before your next commitment."
    )
    assert complete == ["Okay I’ll put the proposal work after your morning meeting,"]
    assert rest.startswith("then keep")


def test_strip_plan_json_block():
    text = 'Sure thing.\n```json\n{"intent":"plan_day","proposed_tasks":[]}\n```'
    visible, raw = strip_plan_json_block(text)
    assert "Sure thing" in visible
    assert raw is not None
    assert "plan_day" in raw


@pytest.mark.asyncio
async def test_turn_cancellation_registry():
    reg = TurnCancellationRegistry()

    async def slow():
        await asyncio.sleep(10)

    task = asyncio.create_task(slow())
    reg.register("t1", task)
    assert reg.cancel("t1") is True
    with pytest.raises(asyncio.CancelledError):
        await task


@pytest.mark.asyncio
async def test_whisper_streaming_stt_buffers_only_during_speech():
    from app.services.whisper_streaming_stt import WhisperStreamingSTT
    from app.config import Settings

    settings = Settings(whisper_stream_partial_interval_ms=0)
    stt = WhisperStreamingSTT(settings)

    pcm = (np.zeros(16000, dtype=np.int16)).tobytes()

    ignored = await stt.feed_audio(pcm)
    assert ignored is None
    assert len(stt._buffer) == 0

    await stt.on_speech_start()
    buffered = await stt.feed_audio(pcm)
    assert buffered is None
    assert len(stt._buffer) == len(pcm)


def test_stt_provider_selects_fish_audio():
    from app.config import Settings
    from app.services.fish_audio_stt import FishAudioStreamingSTT
    from app.services.stt_provider import get_streaming_stt

    settings = Settings(speech_stt_provider="fish_audio", fish_audio_api_key="test")
    assert isinstance(get_streaming_stt(settings), FishAudioStreamingSTT)


@pytest.mark.asyncio
async def test_fish_audio_stt_success():
    from app.config import Settings
    from app.services.fish_audio_stt import FishAudioStreamingSTT

    settings = Settings(speech_stt_provider="fish_audio", fish_audio_api_key="test")
    stt = FishAudioStreamingSTT(settings)
    pcm = (np.ones(4000, dtype=np.int16) * 500).tobytes()

    with patch.object(stt, "_transcribe_wav", new_callable=AsyncMock) as mock_tx:
        mock_tx.return_value = "create a task tomorrow at 5pm"
        await stt.on_speech_start()
        await stt.feed_audio(pcm)
        text = await stt.on_speech_end()

    assert text == "create a task tomorrow at 5pm"
    metrics = stt.consume_metrics()
    assert metrics["stt_provider"] == "fish_audio"
    assert metrics["stt_confidence"] > 0


@pytest.mark.asyncio
async def test_fish_audio_stt_failure_returns_empty_with_metrics():
    from app.config import Settings
    from app.services.fish_audio_stt import FishAudioStreamingSTT

    settings = Settings(speech_stt_provider="fish_audio", fish_audio_api_key="test")
    stt = FishAudioStreamingSTT(settings)
    pcm = (np.ones(4000, dtype=np.int16) * 500).tobytes()

    with patch.object(stt, "_transcribe_wav", new_callable=AsyncMock) as mock_tx:
        mock_tx.side_effect = RuntimeError("no credits")
        await stt.on_speech_start()
        await stt.feed_audio(pcm)
        text = await stt.on_speech_end()

    assert text == ""
    metrics = stt.consume_metrics()
    assert metrics["stt_provider"] == "fish_audio"
    assert metrics["stt_no_speech_probability"] == 1.0


@pytest.mark.asyncio
async def test_whisper_streaming_stt_emits_partial_without_blocking_feed():
    from app.services.whisper_streaming_stt import WhisperStreamingSTT
    from app.config import Settings

    settings = Settings(whisper_stream_partial_interval_ms=0)
    stt = WhisperStreamingSTT(settings)
    pcm = (np.zeros(16000, dtype=np.int16)).tobytes()

    async def fake_transcribe(*, beam_size):
        await asyncio.sleep(0)
        return "I need to schedule"

    with patch.object(stt, "_transcribe", side_effect=fake_transcribe):
        await stt.on_speech_start()
        first = await stt.feed_audio(pcm)
        assert first is None
        await asyncio.sleep(0)
        await asyncio.sleep(0)
        partial = await stt.feed_audio(pcm)
        assert partial == "I need to schedule"
        assert stt.consume_metrics()["stt_partial_ms"] >= 0


@pytest.mark.asyncio
async def test_whisper_streaming_stt_on_speech_end_transcribes():
    from app.services.whisper_streaming_stt import WhisperStreamingSTT
    from app.config import Settings

    settings = Settings(whisper_stream_partial_interval_ms=0)
    stt = WhisperStreamingSTT(settings)
    pcm = (np.zeros(16000, dtype=np.int16)).tobytes()

    with patch.object(stt, "_transcribe", new_callable=AsyncMock) as mock_tx:
        mock_tx.return_value = "hello"
        await stt.on_speech_start()
        await stt.feed_audio(pcm)
        text = await stt.on_speech_end()
        assert text == "hello"
        mock_tx.assert_awaited()


@pytest.mark.asyncio
async def test_run_voice_turn_stream_yields_deltas():
    from app.services.voice_turn import run_voice_turn_stream

    user = MagicMock()
    user.id = "user-1"
    user.timezone = "UTC"
    user.wake_name = "Alex"
    user.display_name = "Alex"
    user.about_me = None

    db = AsyncMock()

    async def fake_stream(*_args, **_kwargs):
        yield {"type": "context_ready", "metrics": {"context_items_count": 1}}
        yield {"type": "reply_delta", "text": "Hi ", "metrics": {"first_token_ms": 1}}
        yield {"type": "reply_delta", "text": "there.", "metrics": {"first_token_ms": 1}}
        yield {"type": "sentence_ready", "text": "Hi there."}
        yield {
            "type": "turn_complete",
            "reply": "Hi there.",
            "mode": "companion",
            "emotion": {"emotion": "neutral", "intensity": 1, "context": "ok"},
            "memories_used": [],
            "suggested_actions": [],
            "plan_draft": None,
            "requires_confirmation": False,
            "confirmation_prompt": None,
            "conversation_id": str(uuid.uuid4()),
            "metrics": {"first_token_ms": 1},
        }

    with patch("app.services.voice_turn.run_companion_turn_stream", new=fake_stream):
        events = []
        async for ev in run_voice_turn_stream(db, user, "hi", "sess-1"):
            events.append(ev)
        deltas = [e for e in events if e["type"] == "reply_delta"]
        assert "".join(d["text"] for d in deltas) == "Hi there."
        assert deltas[0]["metrics"]["first_reply_delta_ms"] >= 0
        meta = [e for e in events if e["type"] == "turn_complete"]
        assert meta and meta[0]["reply"]
        assert "turn_total_ms" in meta[0]["metrics"]


@pytest.mark.asyncio
async def test_generate_companion_response_stream_orders_events():
    from app.services.companion_response_service import generate_companion_response_stream

    async def fake_llm_stream(_messages):
        yield "Hmm, "
        await asyncio.sleep(0)
        yield "that makes sense."

    events = []
    async for event in generate_companion_response_stream(
        user_message="I feel stuck",
        conversation_history=[],
        tasks=[],
        memories=[{"title": "Pending", "content": "hidden", "approval_status": "pending"}],
        goals=[],
        commitments=[],
        projects=[],
        people=[],
        emotional_patterns=[],
        user_preferences={},
        llm_stream=fake_llm_stream,
    ):
        events.append(event)

    types = [event["type"] for event in events]
    assert types.index("context_ready") < types.index("reply_delta")
    assert types.index("reply_delta") < types.index("turn_complete")
    assert types.index("sentence_ready") < types.index("turn_complete")
    assert types.index("post_processing_started") < types.index("turn_complete")
    context_event = next(event for event in events if event["type"] == "context_ready")
    assert context_event["metrics"]["context_items_count"] <= 10
    assert not context_event["context_items_used"]


@pytest.mark.asyncio
async def test_llm_chat_stream_deepseek_parses_sse():
    from app.llm_provider import llm_chat_stream

    lines = [
        'data: {"choices":[{"delta":{"content":"Hello"}}]}',
        "data: [DONE]",
    ]

    class FakeResp:
        def raise_for_status(self):
            return None

        async def aiter_lines(self):
            for line in lines:
                yield line

    class FakeStream:
        async def __aenter__(self):
            return FakeResp()

        async def __aexit__(self, *args):
            return None

    class FakeClient:
        def stream(self, *args, **kwargs):
            return FakeStream()

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

    with patch("app.llm_provider.settings") as mock_settings:
        mock_settings.llm_provider = "deepseek"
        mock_settings.deepseek_api_key = "test-key"
        with patch("app.llm_provider.httpx.AsyncClient", return_value=FakeClient()):
            chunks = []
            async for c in llm_chat_stream([{"role": "user", "content": "hi"}]):
                chunks.append(c)
            assert chunks == ["Hello"]


@pytest.mark.asyncio
async def test_llm_chat_openai_compatible_uses_configured_endpoint():
    from app.llm_provider import llm_chat

    captured = {}

    class FakeResp:
        def raise_for_status(self):
            return None

        def json(self):
            return {"choices": [{"message": {"content": "OpenAI hello"}}]}

    class FakeClient:
        async def post(self, url, **kwargs):
            captured["url"] = url
            captured["kwargs"] = kwargs
            return FakeResp()

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

    with patch("app.llm_provider.settings") as mock_settings:
        mock_settings.llm_provider = "openai"
        mock_settings.openai_api_key = "test-openai-key"
        mock_settings.openai_base_url = "https://api.openai.com/v1"
        mock_settings.openai_model = "gpt-test"
        with patch("app.llm_provider.httpx.AsyncClient", return_value=FakeClient()):
            reply = await llm_chat([{"role": "user", "content": "hi"}])

    assert reply == "OpenAI hello"
    assert captured["url"] == "https://api.openai.com/v1/chat/completions"
    assert captured["kwargs"]["headers"]["Authorization"] == "Bearer test-openai-key"
    assert captured["kwargs"]["json"]["model"] == "gpt-test"


@pytest.mark.asyncio
async def test_llm_chat_stream_openai_compatible_parses_sse():
    from app.llm_provider import llm_chat_stream

    lines = [
        'data: {"choices":[{"delta":{"content":"Hi"}}]}',
        'data: {"choices":[{"delta":{"content":" there"}}]}',
        "data: [DONE]",
    ]

    class FakeResp:
        def raise_for_status(self):
            return None

        async def aiter_lines(self):
            for line in lines:
                yield line

    class FakeStream:
        async def __aenter__(self):
            return FakeResp()

        async def __aexit__(self, *args):
            return None

    class FakeClient:
        def stream(self, *args, **kwargs):
            return FakeStream()

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

    with patch("app.llm_provider.settings") as mock_settings:
        mock_settings.llm_provider = "openai"
        mock_settings.openai_api_key = "test-openai-key"
        mock_settings.openai_base_url = "https://api.openai.com/v1"
        mock_settings.openai_model = "gpt-test"
        with patch("app.llm_provider.httpx.AsyncClient", return_value=FakeClient()):
            chunks = []
            async for c in llm_chat_stream([{"role": "user", "content": "hi"}]):
                chunks.append(c)

    assert chunks == ["Hi", " there"]

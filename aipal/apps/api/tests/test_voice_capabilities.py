import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_voice_capabilities_expose_production_quality_defaults():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        reg = await client.post("/api/v2/auth/register", json={"email": "voice-capabilities@example.com"})
        verify = await client.post("/api/v2/auth/verify", json={"token": reg.json()["dev_token"]})
        headers = {"Authorization": f"Bearer {verify.json()['access_token']}"}

        response = await client.get("/api/v2/voice/capabilities", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["transport"] == "websocket_pcm"
    assert body["live_voice_v2"] is True
    assert body["stt"]["provider"] in {"whisper_stream", "fish_audio"}
    assert isinstance(body["stt"]["configured"], bool)
    assert body["stt"]["automatic_language_detection"] is True
    if body["stt"]["provider"] == "whisper_stream":
        assert body["stt"]["streaming_partials"] is True
        assert body["stt"]["model"] != "tiny"
    assert body["tts"]["provider"] in {"edge", "fish", "local", "espeak", "say"}
    assert isinstance(body["tts"]["configured"], bool)
    assert body["barge_in"]["echo_cancellation_requested"] is True
    assert body["barge_in"]["noise_suppression_requested"] is True
    assert body["barge_in"]["auto_gain_control_requested"] is True

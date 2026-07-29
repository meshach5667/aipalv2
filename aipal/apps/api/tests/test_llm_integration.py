from unittest.mock import AsyncMock, patch
import os
import pytest
from httpx import Response
from app.llm_provider import llm_chat

@pytest.mark.asyncio
async def test_llm_chat_gemini_unit():
    messages = [{"role": "user", "content": "Hello!"}]
    from httpx import Request
    mock_response = Response(
        200,
        json={"choices": [{"message": {"content": "Hi there!"}}]},
        request=Request("POST", "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    )

    from app.config import Settings
    mock_settings = Settings(llm_provider="gemini", gemini_api_key="fake_key", gemini_base_url="https://generativelanguage.googleapis.com/v1beta/openai", gemini_model="gemini-2.0-flash")

    with patch("app.llm_provider.get_settings", return_value=mock_settings), \
         patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
        mock_post.return_value = mock_response
        reply = await llm_chat(messages)
        assert reply == "Hi there!"
        mock_post.assert_called_once()
        args, kwargs = mock_post.call_args
        assert args[0] == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        assert kwargs["headers"]["Authorization"] == "Bearer fake_key"
        assert kwargs["json"]["model"] == "gemini-2.0-flash"

@pytest.mark.skipif("GEMINI_API_KEY" not in os.environ, reason="Missing API key")
@pytest.mark.asyncio
async def test_llm_chat_gemini_integration():
    messages = [{"role": "user", "content": "Return the exact word 'banana' and nothing else."}]
    from app.config import Settings
    mock_settings = Settings(llm_provider="gemini", gemini_api_key=os.environ.get("GEMINI_API_KEY", "dummy"))

    with patch("app.llm_provider.get_settings", return_value=mock_settings):
        reply = await llm_chat(messages)
        assert "banana" in reply.lower()

from httpx import ASGITransport, AsyncClient
from app.main import app

@pytest.mark.skipif("GEMINI_API_KEY" not in os.environ, reason="Missing API key")
@pytest.mark.asyncio
async def test_llm_chat_gemini_system():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        reg = await client.post("/api/v2/auth/register", json={"email": "system-llm-test@example.com"})
        assert reg.status_code == 200, reg.text
        verify = await client.post("/api/v2/auth/verify", json={"token": reg.json()["dev_token"]})
        assert verify.status_code == 200, verify.text
        headers = {"Authorization": f"Bearer {verify.json()['access_token']}"}

        from app.config import Settings
        mock_settings = Settings(llm_provider="gemini", gemini_api_key=os.environ.get("GEMINI_API_KEY", "dummy"))

        with patch("app.llm_provider.get_settings", return_value=mock_settings):
            response = await client.post(
                "/api/v2/turn/text",
                headers=headers,
                json={"text": "My favorite color is strawberry. Can you tell me what my favorite color is?"}
            )
            assert response.status_code == 200, response.text
            body = response.json()
            assert "reply" in body
            assert "strawberry" in body["reply"].lower()

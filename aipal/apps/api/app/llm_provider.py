import json
import logging
from collections.abc import AsyncIterator

import httpx

from .companion_constitution import VOICE_COMPANION_SYSTEM_PROMPT
from .config import get_settings

log = logging.getLogger("aipal.llm")
settings = get_settings()

SYSTEM_PROMPT = VOICE_COMPANION_SYSTEM_PROMPT

VOICE_STREAM_PROMPT_SUFFIX = (
    " Reply in plain spoken language first. If planning JSON is requested in the user message, "
    "append it only after your spoken reply inside a ```json fenced block."
)


async def llm_chat(messages: list[dict[str, str]]) -> str:
    if not settings.gemini_api_key or settings.gemini_api_key == "dummy":
        return "I cannot connect right now because the Gemini API key is missing or invalid. Please check your configuration."
    try:
        return await _gemini_chat(messages)
    except (httpx.HTTPError, OSError) as exc:
        log.warning("LLM provider unavailable; using local fallback reply: %s", exc)
        return _fallback_reply(messages)


async def llm_chat_stream(messages: list[dict[str, str]]) -> AsyncIterator[str]:
    if not settings.gemini_api_key or settings.gemini_api_key == "dummy":
        yield "I cannot connect right now because the Gemini API key is missing or invalid. Please check your configuration."
        return
    try:
        async for chunk in _gemini_chat_stream(messages):
            yield chunk
        return
    except (httpx.HTTPError, OSError) as exc:
        log.warning("Streaming LLM provider unavailable; using local fallback reply: %s", exc)
        text = _fallback_reply(messages)
    yield text


async def _gemini_chat(messages: list[dict[str, str]]) -> str:
    headers = {"Authorization": f"Bearer {settings.gemini_api_key}"} if settings.gemini_api_key else {}
    async with httpx.AsyncClient(timeout=settings.gemini_timeout_seconds) as client:
        resp = await client.post(
            f"{settings.gemini_base_url.rstrip('/')}/chat/completions",
            headers=headers,
            json={
                "model": settings.gemini_model,
                "messages": _with_default_system(messages),
                "max_tokens": settings.gemini_max_tokens,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


async def _gemini_chat_stream(messages: list[dict[str, str]]) -> AsyncIterator[str]:
    headers = {"Authorization": f"Bearer {settings.gemini_api_key}"} if settings.gemini_api_key else {}
    async with httpx.AsyncClient(timeout=settings.gemini_timeout_seconds) as client:
        async with client.stream(
            "POST",
            f"{settings.gemini_base_url.rstrip('/')}/chat/completions",
            headers=headers,
            json={
                "model": settings.gemini_model,
                "messages": _with_default_system(messages, suffix=VOICE_STREAM_PROMPT_SUFFIX),
                "max_tokens": settings.gemini_max_tokens,
                "stream": True,
            },
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.startswith("data: "):
                    continue
                payload = line[6:].strip()
                if payload == "[DONE]":
                    break
                try:
                    data = json.loads(payload)
                    delta = data["choices"][0].get("delta", {}).get("content")
                    if delta:
                        yield delta
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue


async def llm_chat_json(messages: list[dict[str, str]]) -> dict:
    import re

    text = await llm_chat(messages)
    text = text.strip()
    if m := re.search(r"\{[\s\S]*\}", text):
        text = m.group(0)
    return json.loads(text)


def _with_default_system(messages: list[dict[str, str]], *, suffix: str = "") -> list[dict[str, str]]:
    has_system = False
    new_messages = []
    for msg in messages:
        if msg.get("role") == "system":
            has_system = True
            if suffix:
                # Append suffix to the first system message
                new_msg = msg.copy()
                new_msg["content"] = str(new_msg.get("content", "")) + suffix
                new_messages.append(new_msg)
                suffix = ""  # Only append to the first one
            else:
                new_messages.append(msg)
        else:
            new_messages.append(msg)

    if not has_system:
        return [{"role": "system", "content": SYSTEM_PROMPT + suffix}, *messages]
    return new_messages


def _fallback_reply(messages: list[dict[str, str]]) -> str:
    user_text = ""
    for message in reversed(messages):
        if message.get("role") == "user":
            user_text = (message.get("content") or "").strip()
            break
    if "[Context:" in user_text or "[State:" in user_text:
        user_text = user_text.rsplit("]\n\n", 1)[-1].strip()
    if not user_text:
        return "I am here with you. Tell me what is on your mind, and we can think it through together."
    if "?" in user_text:
        return "I hear the question. I can still help you reason through it, but my deeper AI connection is offline right now. What matters most about this decision?"
    return "I hear you. My deeper AI connection is offline right now, but I am still here with you. Say a little more, and we can keep working through it."

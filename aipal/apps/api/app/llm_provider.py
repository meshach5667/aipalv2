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
    for provider in _provider_order():
        try:
            if provider in {"openai", "openai_compatible"}:
                return await _openai_chat(messages)
            if provider == "deepseek":
                return await _deepseek_chat(messages)
            if provider == "ollama":
                return await _ollama_chat(messages)
        except (httpx.HTTPError, OSError) as exc:
            log.warning("LLM provider %s unavailable: %s", provider, _provider_error(exc))
            continue
    log.warning("No configured LLM provider succeeded; using local fallback reply")
    return _fallback_reply(messages)


async def llm_chat_stream(messages: list[dict[str, str]]) -> AsyncIterator[str]:
    for provider in _provider_order():
        try:
            if provider in {"openai", "openai_compatible"}:
                async for chunk in _openai_chat_stream(messages):
                    yield chunk
                return
            if provider == "deepseek":
                async for chunk in _deepseek_chat_stream(messages):
                    yield chunk
                return
            if provider == "ollama":
                yield await _ollama_chat(messages)
                return
        except (httpx.HTTPError, OSError) as exc:
            log.warning("Streaming LLM provider %s unavailable: %s", provider, _provider_error(exc))
            continue
    log.warning("No configured streaming LLM provider succeeded; using local fallback reply")
    yield _fallback_reply(messages)


def _provider_order() -> list[str]:
    preferred = settings.llm_provider.lower().strip()
    available: list[str] = []
    if settings.deepseek_api_key:
        available.append("deepseek")
    if settings.openai_api_key:
        available.append("openai")
    if preferred == "ollama" or not available:
        available.append("ollama")

    ordered = [provider for provider in (preferred, *available) if provider in {"deepseek", "openai", "openai_compatible", "ollama"}]
    if preferred == "openai_compatible" and settings.openai_api_key:
        ordered.append("openai")
    return list(dict.fromkeys(provider for provider in ordered if _provider_configured(provider)))


def _provider_configured(provider: str) -> bool:
    if provider in {"openai", "openai_compatible"}:
        return bool(settings.openai_api_key)
    if provider == "deepseek":
        return bool(settings.deepseek_api_key)
    return provider == "ollama"


def _provider_error(exc: Exception) -> str:
    if isinstance(exc, httpx.HTTPStatusError):
        response_text = exc.response.text[:300] if exc.response is not None else ""
        return f"HTTP {exc.response.status_code}: {response_text}"
    return str(exc)


def llm_status() -> dict[str, object]:
    return {
        "provider": settings.llm_provider,
        "provider_order": _provider_order(),
        "deepseek_configured": bool(settings.deepseek_api_key),
        "openai_configured": bool(settings.openai_api_key),
        "openai_base_url": settings.openai_base_url,
        "openai_model": settings.openai_model,
        "ollama_configured": True,
        "ollama_base_url": settings.ollama_base_url,
    }


async def llm_ping() -> dict[str, object]:
    messages = [
        {"role": "system", "content": "Reply with exactly: ok"},
        {"role": "user", "content": "health check"},
    ]
    errors: list[dict[str, str]] = []
    for provider in _provider_order():
        try:
            if provider in {"openai", "openai_compatible"}:
                reply = await _openai_chat(messages)
            elif provider == "deepseek":
                reply = await _deepseek_chat(messages)
            else:
                reply = await _ollama_chat(messages)
            return {
                "ok": True,
                "provider": provider,
                "reply_preview": reply[:80],
                **llm_status(),
            }
        except (httpx.HTTPError, OSError) as exc:
            errors.append({"provider": provider, "error": _provider_error(exc)})
    return {"ok": False, "errors": errors, **llm_status()}


async def _deepseek_chat(messages: list[dict[str, str]]) -> str:
    async with httpx.AsyncClient(timeout=settings.deepseek_timeout_seconds) as client:
        resp = await client.post(
            "https://api.deepseek.com/chat/completions",
            headers={"Authorization": f"Bearer {settings.deepseek_api_key}"},
            json={
                "model": "deepseek-chat",
                "messages": _with_default_system(messages),
                "max_tokens": settings.deepseek_max_tokens,
                "temperature": 0.25,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


async def _deepseek_chat_stream(messages: list[dict[str, str]]) -> AsyncIterator[str]:
    async with httpx.AsyncClient(timeout=settings.deepseek_timeout_seconds) as client:
        async with client.stream(
            "POST",
            "https://api.deepseek.com/chat/completions",
            headers={"Authorization": f"Bearer {settings.deepseek_api_key}"},
            json={
                "model": "deepseek-chat",
                "messages": _with_default_system(messages, suffix=VOICE_STREAM_PROMPT_SUFFIX),
                "max_tokens": settings.deepseek_max_tokens,
                "temperature": 0.25,
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


async def _openai_chat(messages: list[dict[str, str]]) -> str:
    async with httpx.AsyncClient(timeout=settings.openai_timeout_seconds) as client:
        resp = await client.post(
            f"{settings.openai_base_url.rstrip('/')}/chat/completions",
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            json={
                "model": settings.openai_model,
                "messages": _with_default_system(messages),
                "max_tokens": settings.openai_max_tokens,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


async def _openai_chat_stream(messages: list[dict[str, str]]) -> AsyncIterator[str]:
    async with httpx.AsyncClient(timeout=settings.openai_timeout_seconds) as client:
        async with client.stream(
            "POST",
            f"{settings.openai_base_url.rstrip('/')}/chat/completions",
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            json={
                "model": settings.openai_model,
                "messages": _with_default_system(messages, suffix=VOICE_STREAM_PROMPT_SUFFIX),
                "max_tokens": settings.openai_max_tokens,
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


async def _ollama_chat(messages: list[dict[str, str]]) -> str:
    async with httpx.AsyncClient(timeout=settings.ollama_timeout_seconds) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/chat",
            json={
                "model": settings.ollama_model,
                "messages": _with_default_system(messages),
                "stream": False,
                "options": {
                    "num_predict": max(48, settings.ollama_num_predict),
                    "temperature": settings.ollama_temperature,
                },
            },
        )
        resp.raise_for_status()
        return resp.json()["message"]["content"]


def _with_default_system(messages: list[dict[str, str]], *, suffix: str = "") -> list[dict[str, str]]:
    if any(message.get("role") == "system" for message in messages):
        return messages
    return [{"role": "system", "content": SYSTEM_PROMPT + suffix}, *messages]


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

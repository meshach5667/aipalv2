import asyncio
import logging
import re
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

from .config import get_settings
from .db import async_session, engine, init_db
from .jobs.notification_dispatcher import dispatch_due_notifications
from .routers import (
    accountability,
    auth,
    brain,
    calendar,
    commitments,
    connectors,
    coaching,
    companion,
    business,
    daily,
    focus,
    life_dashboard,
    life_map,
    life_story,
    growth_plans,
    insights,
    integrations,
    habits,
    knowledge,
    memory_insights,
    meetings,
    notifications,
    planner,
    proactive,
    understanding,
    profile,
    project_rooms,
    reminders,
    relationship,
    tasks,
    today,
    today_items,
    turn,
    weekly_reviews,
    ws_session,
)
from .schemas import HealthResponse

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("aipal")
settings = get_settings()
_LOCAL_DEV_ORIGIN_RE = re.compile(r"^https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$")


def _cors_kwargs() -> dict:
    if settings.cors_origins == "*":
        return {"allow_origin_regex": r"https?://.*"}
    return {"allow_origins": [origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()]}


def _cors_origin_allowed(origin: str | None) -> bool:
    if not origin:
        return False
    if _LOCAL_DEV_ORIGIN_RE.match(origin):
        return True
    if settings.cors_origins == "*":
        return origin.startswith(("http://", "https://"))
    return origin in {item.strip() for item in settings.cors_origins.split(",") if item.strip()}


def _ensure_cors_headers(response: Response, origin: str | None) -> Response:
    """Defensive CORS fallback for browser-visible errors in local/dev builds."""
    if not _cors_origin_allowed(origin):
        return response
    response.headers.setdefault("access-control-allow-origin", origin or "")
    response.headers.setdefault("access-control-allow-credentials", "true")
    response.headers.setdefault("access-control-allow-methods", "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT")
    response.headers.setdefault("access-control-allow-headers", "authorization, content-type")
    vary = response.headers.get("vary")
    if not vary:
        response.headers["vary"] = "Origin"
    elif "origin" not in vary.lower():
        response.headers["vary"] = f"{vary}, Origin"
    return response


async def _prewarm_whisper() -> None:
    """Load faster-whisper at startup so first Live turn is not blocked on HF download."""
    if not settings.live_voice_v2:
        return
    if (settings.stt_provider or "").lower() != "whisper_stream":
        return
    try:
        from .stt import _get_model

        await asyncio.to_thread(_get_model)
        log.info(
            "Whisper STT pre-warmed (model=%s device=%s)",
            settings.whisper_model,
            settings.whisper_device,
        )
    except Exception:
        log.exception("Whisper STT pre-warm failed; first turn may be slow")


async def _notification_dispatcher_loop() -> None:
    if not settings.notification_dispatcher_enabled:
        return
    interval = max(5, int(settings.notification_dispatcher_interval_seconds))
    log.info("Notification dispatcher started (interval=%ss)", interval)
    while True:
        try:
            async with async_session() as db:
                result = await dispatch_due_notifications(db)
                if result.get("sent") or result.get("failed"):
                    log.info("Notification dispatcher result: %s", result)
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("Notification dispatcher cycle failed")
        await asyncio.sleep(interval)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    await _prewarm_whisper()
    dispatcher_task = asyncio.create_task(_notification_dispatcher_loop())
    log.info("AIpal API v2 started")
    try:
        yield
    finally:
        dispatcher_task.cancel()
        try:
            await dispatcher_task
        except asyncio.CancelledError:
            pass
    await engine.dispose()


app = FastAPI(title="AIpal API v2", version="2.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    **_cors_kwargs(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def cors_error_fallback(request: Request, call_next):
    origin = request.headers.get("origin")
    try:
        response = await call_next(request)
    except Exception:
        log.exception("Unhandled request failed")
        response = JSONResponse({"detail": "Internal server error"}, status_code=500)
    return _ensure_cors_headers(response, origin)

prefix = "/api/v2"
app.include_router(auth.router, prefix=prefix)
app.include_router(brain.router, prefix=prefix)
app.include_router(profile.router, prefix=prefix)
app.include_router(reminders.router, prefix=prefix)
app.include_router(coaching.router, prefix=prefix)
app.include_router(growth_plans.router, prefix=prefix)
app.include_router(accountability.router, prefix=prefix)
app.include_router(habits.router, prefix=prefix)
app.include_router(knowledge.router, prefix=prefix)
app.include_router(commitments.router, prefix=prefix)
app.include_router(proactive.router, prefix=prefix)
app.include_router(understanding.router, prefix=prefix)
app.include_router(life_story.router, prefix=prefix)
app.include_router(life_dashboard.router, prefix=prefix)
app.include_router(connectors.router, prefix=prefix)
app.include_router(business.router, prefix=prefix)
app.include_router(tasks.router, prefix=prefix)
app.include_router(today.router, prefix=prefix)
app.include_router(today_items.router, prefix=prefix)
app.include_router(focus.router, prefix=prefix)
app.include_router(notifications.router, prefix=prefix)
app.include_router(planner.router, prefix=prefix)
app.include_router(project_rooms.router, prefix=prefix)
app.include_router(life_map.router, prefix=prefix)
app.include_router(daily.router, prefix=prefix)
app.include_router(companion.router, prefix=prefix)
app.include_router(relationship.router, prefix=prefix)
app.include_router(memory_insights.router, prefix=prefix)
app.include_router(meetings.router, prefix=prefix)
app.include_router(insights.router, prefix=prefix)
app.include_router(weekly_reviews.router, prefix=prefix)
app.include_router(turn.router, prefix=prefix)
app.include_router(calendar.router, prefix=prefix)
app.include_router(integrations.router, prefix=prefix)
app.include_router(ws_session.router, prefix=prefix)
app.include_router(auth.router)


@app.get("/api/v2/health", response_model=HealthResponse)
async def health():
    return HealthResponse(ok=True, mem0_enabled=settings.mem0_enabled, llm_provider=settings.llm_provider)


@app.get("/health")
async def health_root():
    return {"ok": True, "service": "aipal-v2"}

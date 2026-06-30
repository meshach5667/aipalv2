"""Calendar import (v2.1) — read-only device event cache."""

from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth import get_current_user
from ..db import get_db
from ..models import CalendarEventCache, User

router = APIRouter(prefix="/calendar", tags=["calendar"])


class CalendarEventIn(BaseModel):
    external_id: str
    title: str
    starts_at: datetime
    ends_at: datetime | None = None


class CalendarImportRequest(BaseModel):
    events: list[CalendarEventIn]


class CalendarImportResponse(BaseModel):
    imported: int


@router.post("/import", response_model=CalendarImportResponse)
async def import_events(
    body: CalendarImportRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(delete(CalendarEventCache).where(CalendarEventCache.user_id == user.id))
    for ev in body.events:
        db.add(
            CalendarEventCache(
                user_id=user.id,
                external_id=ev.external_id,
                title=ev.title,
                starts_at=ev.starts_at,
                ends_at=ev.ends_at,
            )
        )
    await db.commit()
    return CalendarImportResponse(imported=len(body.events))


@router.get("/today")
async def today_events(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import select

    result = await db.execute(
        select(CalendarEventCache).where(CalendarEventCache.user_id == user.id).order_by(CalendarEventCache.starts_at)
    )
    events = result.scalars().all()
    return [
        {"id": e.id, "title": e.title, "starts_at": e.starts_at.isoformat(), "ends_at": e.ends_at.isoformat() if e.ends_at else None}
        for e in events
    ]

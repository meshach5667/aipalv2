from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from ..models import User
from . import plan_draft as draft_svc
from .today_item_service import list_today_items


def _dt(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime.combine(day, time(hour=hour, minute=minute))


def _draft_item(day: date, hour: int, title: str, *, category: str = "work", minutes: int = 45, priority: int = 1) -> dict[str, Any]:
    return {
        "title": title,
        "due_at": _dt(day, hour).isoformat(),
        "estimated_minutes": minutes,
        "priority": priority,
        "category": category,
        "notes": "Planner draft. Confirm before adding to Today.",
    }


async def _existing_constraints(db: AsyncSession, user_id, day: date) -> list[dict[str, Any]]:
    return [
        {
            "title": item.title,
            "type": item.type,
            "start_time": item.start_time.isoformat() if item.start_time else None,
            "due_at": item.due_at.isoformat() if item.due_at else None,
        }
        for item in await list_today_items(db, user_id, day)
        if item.status not in {"completed", "cancelled", "dismissed"}
    ]


async def balance_plan(db: AsyncSession, user_id, plan: list[dict[str, Any]], constraints: list[dict[str, Any]]) -> list[dict[str, Any]]:
    busy_hours = set()
    for item in constraints:
        raw = item.get("start_time") or item.get("due_at")
        if raw:
            parsed = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
            busy_hours.add(parsed.hour)
    balanced = []
    for item in plan:
        due_at = datetime.fromisoformat(str(item["due_at"]).replace("Z", "+00:00"))
        while due_at.hour in busy_hours and due_at.hour < 17:
            due_at += timedelta(hours=1)
        busy_hours.add(due_at.hour)
        item = dict(item)
        item["due_at"] = due_at.isoformat()
        balanced.append(item)
    return balanced


async def _save_plan(db: AsyncSession, user: User, intent: str, proposed_tasks: list[dict[str, Any]], *, clarifying_question: str | None = None) -> dict[str, Any]:
    payload = {
        "intent": intent,
        "proposed_tasks": proposed_tasks,
        "clarifying_question": clarifying_question,
        "requires_confirmation": True,
    }
    await draft_svc.save_draft(db, user.id, payload)
    return payload


async def generate_daily_plan(db: AsyncSession, user: User, target_date: date | None = None) -> dict[str, Any]:
    day = target_date or date.today()
    constraints = await _existing_constraints(db, user.id, day)
    base = [
        _draft_item(day, 8, "Morning review", category="reflection", minutes=20),
        _draft_item(day, 10, "Focused work block", category="focus", minutes=60, priority=2),
        _draft_item(day, 13, "Admin and follow-ups", category="admin", minutes=40),
        _draft_item(day, 16, "Review progress and next step", category="review", minutes=25),
    ]
    balanced = await balance_plan(db, user.id, base, constraints)
    return await _save_plan(db, user, "daily_plan", balanced)


async def generate_weekly_plan(db: AsyncSession, user: User, week_start: date | None = None) -> dict[str, Any]:
    start = week_start or (date.today() - timedelta(days=date.today().weekday()))
    tasks: list[dict[str, Any]] = []
    themes = [
        "Set weekly priorities",
        "Deep work on main project",
        "Relationship and follow-up block",
        "Review commitments",
        "Weekly reflection",
    ]
    for offset, title in enumerate(themes):
        day = start + timedelta(days=offset)
        constraints = await _existing_constraints(db, user.id, day)
        item = _draft_item(day, 10 if offset < 4 else 15, title, category="weekly", minutes=50)
        tasks.extend(await balance_plan(db, user.id, [item], constraints))
    return await _save_plan(db, user, "weekly_plan", tasks)


async def generate_monthly_plan(db: AsyncSession, user: User, month: str | None = None) -> dict[str, Any]:
    today = date.today()
    start = date.fromisoformat(f"{month}-01") if month else today.replace(day=1)
    tasks = [
        _draft_item(start, 9, "Choose the month’s top outcome", category="monthly", minutes=45, priority=2),
        _draft_item(start + timedelta(days=7), 10, "Review project milestones", category="monthly", minutes=45),
        _draft_item(start + timedelta(days=14), 10, "Mid-month adjustment", category="monthly", minutes=35),
        _draft_item(start + timedelta(days=24), 15, "Monthly review and lessons", category="reflection", minutes=45),
    ]
    return await _save_plan(db, user, "monthly_plan", tasks)


async def generate_quarterly_plan(db: AsyncSession, user: User, quarter: str | None = None) -> dict[str, Any]:
    today = date.today()
    tasks = [
        _draft_item(today, 9, "Define quarterly outcomes", category="quarterly", minutes=60, priority=2),
        _draft_item(today + timedelta(days=30), 10, "Quarter checkpoint", category="quarterly", minutes=45),
        _draft_item(today + timedelta(days=60), 10, "Quarter execution review", category="quarterly", minutes=45),
    ]
    return await _save_plan(db, user, "quarterly_plan", tasks)


async def generate_90_day_plan(db: AsyncSession, user: User, goal_id: UUID | None = None) -> dict[str, Any]:
    today = date.today()
    tasks = [
        _draft_item(today, 9, "Clarify 90-day target", category="roadmap", minutes=50, priority=2),
        _draft_item(today + timedelta(days=30), 9, "30-day milestone review", category="roadmap", minutes=40),
        _draft_item(today + timedelta(days=60), 9, "60-day milestone review", category="roadmap", minutes=40),
        _draft_item(today + timedelta(days=88), 15, "90-day reflection and next roadmap", category="roadmap", minutes=50),
    ]
    if goal_id:
        for task in tasks:
            task["goal_id"] = str(goal_id)
    return await _save_plan(db, user, "90_day_plan", tasks)


async def generate_goal_roadmap(db: AsyncSession, user: User, goal_id: UUID) -> dict[str, Any]:
    return await generate_90_day_plan(db, user, goal_id=goal_id)


async def generate_life_roadmap(db: AsyncSession, user: User) -> dict[str, Any]:
    today = date.today()
    tasks = [
        _draft_item(today, 9, "Review life areas", category="life_roadmap", minutes=45),
        _draft_item(today + timedelta(days=7), 9, "Choose one area to improve", category="life_roadmap", minutes=45),
        _draft_item(today + timedelta(days=14), 9, "Create support rhythm", category="life_roadmap", minutes=45),
    ]
    return await _save_plan(db, user, "life_roadmap", tasks)


async def convert_plan_to_today_items(db: AsyncSession, user: User, draft_id: str = "current") -> list[dict[str, Any]]:
    return await draft_svc.confirm_draft(db, user.id, timezone=user.timezone or "UTC")

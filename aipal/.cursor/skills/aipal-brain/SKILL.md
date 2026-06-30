---
name: aipal-brain
description: >-
  AiPal conversational brain: session_id, conversation_turns, plan_extractor →
  plan_draft → confirm flow. No stateless chat, no silent task creation. Use when
  editing turn/text, plan drafts, conversation memory, or testing 4pm/6pm scenarios.
---

# AiPal Brain

## Turn pipeline (required pattern)

```
POST /turn/text  { text, session_id? }
  → load conversation_turns for session_id
  → plan_extractor.extract_plan (LLM JSON)
  → save plan_draft (never auto-create tasks)
  → append turns to conversation_turns
  → return { reply, session_id, plan_draft? }

User confirms → POST /tasks/plan-draft/confirm → tasks created
User declines → POST /tasks/plan-draft/discard
```

Key files:
- `apps/api/app/routers/turn.py` — text/audio turn handler
- `apps/api/app/services/plan_extractor.py` — LLM plan JSON extraction
- `apps/api/app/services/plan_draft.py` — draft persistence + confirm
- `apps/api/app/services/conversation.py` — `conversation_turns` storage
- `apps/mobile/lib/providers/app_state.dart` — `sendTextTurn`, `confirmPlanDraft`

## Rules

1. **Always use `session_id`** — reuse across turns in a chat/Live session; never treat turns as isolated.
2. **Never silently create tasks** — extracted plans go to `plan_drafts`; user must confirm.
3. **No stateless chat** — load recent history before LLM reply (`conversation_turns`).
4. **Priority scale** — `0=low, 1=medium, 2=high` in extractor output.
5. **Concise titles** — `plan_extractor` must produce 1–4 word titles; put user phrasing in `notes`. Never commit raw speech as title.
6. **Confirm intent** — `plan_intent.is_confirm_intent` handles "yes add to today" before re-extracting.
7. **Today is operational state** — every turn injects `today_view` snapshot (open count, up next) into system context in `turn.py`. The LLM should treat Today as ground truth for the user's day, not invent parallel task lists.
8. **No push-to-talk copy** — never say hold/tap/press to talk in LLM replies or Live greetings (`in_live=true` on `/daily/live-greeting`).
9. **User-local today** — `today-view` default day uses `user.timezone` via `timezone_util.user_local_today`.

## Test scenarios

Run: `cd apps/api && pytest tests/test_brain_v11.py -q`

| Scenario | Input | Expected |
|----------|-------|----------|
| 4pm/6pm plan | `"meeting by 4pm and swimming by 6pm"` | `plan_draft` with 2 tasks, due times set |
| Multi-turn | Turn 1: `"meeting by 4pm"` → Turn 2: `"actually swim at 7"` same `session_id` | Second reply references prior context |
| Confirm | `POST /tasks/plan-draft/confirm` | Tasks appear in `today-view` |

Mock `plan_extractor.extract_plan` and `llm_chat` in unit tests; smoke test tolerates LLM offline for draft step.

## Mobile plan draft UI

- `apps/mobile/lib/widgets/plan_draft_card.dart` — Confirm / Not now
- `apps/mobile/lib/screens/text_chat_screen.dart` — shows draft after turn
- Today screen also surfaces drafts from `POST /tasks/suggest-day`

from app.conversation.reasoning import ReasoningDecision
from app.services.response_quality import evaluate_response_quality


def _decision(**updates):
    payload = {
        "schema_version": "1.0",
        "intents": [{"name": "schedule_meeting", "confidence": 0.9}],
        "primary_intent": "schedule_meeting",
        "complexity": "high",
        "requires_tools": True,
        "requires_memory": True,
        "requires_live_data": True,
        "missing_information": [],
        "mode": "assistant",
        "emotion": {"emotion": "neutral", "intensity": 1, "urgency": 0},
        "conversation_strategy": "Schedule a meeting only with verified tools.",
        "response_strategy": "Report verified state.",
        "planning_notes": [],
        "tool_calls": [],
        "confirmation_message": None,
        "pending_action_resolution": "none",
    }
    payload.update(updates)
    return ReasoningDecision.model_validate(payload)


def test_quality_gate_rejects_false_success_and_generic_response():
    evaluation = evaluate_response_quality(
        user_message="Schedule a meeting with Jordan.",
        reply="Here are some suggestions. I scheduled the meeting.",
        decision=_decision(),
        context_items=[],
        tool_results=[],
        validation_errors=[],
    )

    assert evaluation.requires_revision is True
    assert evaluation.too_generic is True
    assert evaluation.unsupported_claims


def test_quality_gate_accepts_grounded_tool_result():
    evaluation = evaluate_response_quality(
        user_message="What tasks are open?",
        reply="You have two open tasks from your task list.",
        decision=_decision(
            primary_intent="memory_recall",
            complexity="standard",
            requires_tools=True,
            requires_memory=False,
            requires_live_data=False,
        ),
        context_items=[],
        tool_results=[{"call_id": "tasks", "tool": "task_service", "status": "completed"}],
        validation_errors=[],
    )

    assert evaluation.requires_revision is False

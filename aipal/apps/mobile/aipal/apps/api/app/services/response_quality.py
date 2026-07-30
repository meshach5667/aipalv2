"""Deterministic response-quality checks for important assistant turns."""

from __future__ import annotations

import time
from typing import Any

from ..conversation.contracts import ResponseEvaluation
from ..conversation.reasoning import ReasoningDecision


GENERIC_PHRASES = (
    "here are some suggestions",
    "it depends",
    "you may want to",
    "there are several ways",
)


def evaluate_response_quality(
    *,
    user_message: str,
    reply: str,
    decision: ReasoningDecision,
    context_items: list[dict[str, Any]],
    tool_results: list[dict[str, Any]],
    validation_errors: list[str],
) -> ResponseEvaluation:
    started = time.perf_counter()
    normalized_reply = (reply or "").strip().lower()
    normalized_request = (user_message or "").strip().lower()
    unsupported_claims: list[str] = []
    missing_steps: list[str] = list(validation_errors)

    completed_tool_actions = [
        result for result in tool_results if result.get("status", "completed") == "completed"
    ]
    if any(word in normalized_reply for word in ("created", "scheduled", "cancelled", "saved")):
        if not completed_tool_actions:
            unsupported_claims.append("Response claims a completed action without a verified tool result")

    requires_context = bool(decision.requires_memory or decision.requires_live_data)
    used_relevant_context = not requires_context or bool(context_items or tool_results)
    too_generic = any(phrase in normalized_reply for phrase in GENERIC_PHRASES)
    if len(normalized_reply.split()) < 8 and decision.complexity.value == "high":
        too_generic = True
    if normalized_reply and normalized_reply == normalized_request:
        too_generic = True

    answered_request = bool(normalized_reply) and not normalized_reply == normalized_request
    completed_requested_actions = not decision.requires_tools or bool(
        completed_tool_actions or decision.missing_information or validation_errors
    )

    requires_revision = bool(
        unsupported_claims
        or missing_steps
        or too_generic
        or not answered_request
        or not used_relevant_context
    )
    return ResponseEvaluation(
        answered_request=answered_request,
        used_relevant_context=used_relevant_context,
        completed_requested_actions=completed_requested_actions,
        unsupported_claims=unsupported_claims,
        missing_steps=missing_steps,
        too_generic=too_generic,
        requires_revision=requires_revision,
        validation_ms=int((time.perf_counter() - started) * 1_000),
    )

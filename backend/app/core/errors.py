"""
Centralized error handling for agent/API failures.
Constants and a reusable helper so routes stay thin and new error types are easy to add.
"""
from __future__ import annotations

from typing import Callable

from fastapi import HTTPException

# ---------------------------------------------------------------------------
# Constants: status codes and user-facing messages
# ---------------------------------------------------------------------------

# AI / OpenAI
OPENAI_BILLING_URL = "https://platform.openai.com/account/billing"
MSG_AI_QUOTA_EXCEEDED = (
    "AI service quota exceeded. Check your OpenAI plan and billing at {url}"
).format(url=OPENAI_BILLING_URL)

# HTTP status codes for known error categories
STATUS_SERVICE_UNAVAILABLE = 503  # quota, rate limit, provider down
STATUS_INTERNAL_ERROR = 500


# ---------------------------------------------------------------------------
# Error rules: (predicate, status_code, detail_message)
# Add new rules here instead of scattering checks in routes.
# ---------------------------------------------------------------------------

def _is_quota_error(msg: str) -> bool:
    lower = msg.lower()
    return (
        "429" in msg
        or "insufficient_quota" in lower
        or "quota" in lower
        or "rate limit" in lower
    )


# List of (predicate, status_code, detail). First match wins.
AGENT_ERROR_RULES: list[tuple[Callable[[str], bool], int, str]] = [
    (_is_quota_error, STATUS_SERVICE_UNAVAILABLE, MSG_AI_QUOTA_EXCEEDED),
]


def agent_error_to_http(exc: Exception) -> HTTPException:
    """
    Map an exception from agent/orchestrator run into an HTTPException.
    Uses AGENT_ERROR_RULES for known error types; otherwise returns 500 with the exception message.
    """
    msg = str(exc)
    for predicate, status_code, detail in AGENT_ERROR_RULES:
        if predicate(msg):
            return HTTPException(status_code=status_code, detail=detail)
    return HTTPException(status_code=STATUS_INTERNAL_ERROR, detail=msg)

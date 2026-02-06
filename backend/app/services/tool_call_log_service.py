"""
Append and list tool call logs for the Log tab.
Keeps input args only (no huge payloads); truncates long lists for display.
"""
import json
from typing import Any

from sqlalchemy.orm import Session

from app.models.tool_call_log import ToolCallLog

MAX_LIST_LEN = 50


def _sanitize(value: Any) -> Any:
    """Truncate long lists for storage/display."""
    if isinstance(value, list):
        if len(value) <= MAX_LIST_LEN:
            return [_sanitize(v) for v in value]
        return [_sanitize(v) for v in value[:MAX_LIST_LEN]] + [f"... ({len(value)} total)"]
    if isinstance(value, dict):
        return {k: _sanitize(v) for k, v in value.items()}
    return value


def log_tool_call(
    db: Session,
    tool_name: str,
    arguments: dict[str, Any],
    session_id: str | None = None,
) -> None:
    """Append one tool call log entry. Call at the start of each tool."""
    try:
        sanitized = _sanitize(arguments)
        payload = json.dumps(sanitized, default=str)
    except (TypeError, ValueError):
        payload = json.dumps({"raw": str(arguments)[:2000]})
    row = ToolCallLog(
        tool_name=tool_name,
        arguments_json=payload,
        session_id=session_id,
    )
    db.add(row)
    db.commit()


def get_recent_logs(db: Session, limit: int = 100) -> list[dict]:
    """Return recent tool call log entries for the Log tab, newest first."""
    rows = (
        db.query(ToolCallLog)
        .order_by(ToolCallLog.created_at.desc())
        .limit(limit)
        .all()
    )
    out = []
    for r in rows:
        args = None
        if r.arguments_json:
            try:
                args = json.loads(r.arguments_json)
            except (TypeError, json.JSONDecodeError):
                args = {"_raw": r.arguments_json[:500]}
        out.append({
            "id": r.id,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "tool_name": r.tool_name,
            "arguments": args,
            "session_id": r.session_id,
        })
    return out

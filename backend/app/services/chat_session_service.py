"""
Chat session: get and save message history per session (for Pydantic AI message_history).
Uses pydantic_ai ModelMessagesTypeAdapter to serialize/deserialize.
Also stores last venue search per session for sidebar display (same data as snapshot/compare).
"""
import json
import uuid
from datetime import datetime, timezone

from pydantic_ai import ModelMessagesTypeAdapter
from pydantic_ai.messages import ModelRequest, ModelResponse
from sqlalchemy.orm import Session

from app.models.chat_session import ChatSession


def get_messages(db: Session, session_id: str) -> list:
    """
    Load message history for a session. Returns list of ModelMessage (empty if none).
    """
    row = db.query(ChatSession).filter(ChatSession.session_id == session_id).first()
    if not row or not row.message_list or not row.message_list.strip():
        return []
    try:
        return ModelMessagesTypeAdapter.validate_json(row.message_list.encode("utf-8"))
    except Exception:
        return []


def _text_from_parts(parts: list) -> str:
    """Extract and join text content from message parts."""
    bits = []
    for p in parts:
        c = getattr(p, "content", None)
        if isinstance(c, str):
            bits.append(c)
    return "\n".join(bits) if bits else ""


def get_messages_for_display(db: Session, session_id: str) -> list[dict]:
    """
    Load message history for a session as simple { role, content } for the frontend.
    """
    raw = get_messages(db, session_id)
    out = []
    for msg in raw:
        if isinstance(msg, ModelRequest):
            text = _text_from_parts(getattr(msg, "parts", []) or [])
            if text:
                out.append({"role": "user", "content": text})
        elif isinstance(msg, ModelResponse):
            text = _text_from_parts(getattr(msg, "parts", []) or [])
            if text:
                out.append({"role": "assistant", "content": text})
    return out


def save_messages(db: Session, session_id: str, messages_json_bytes: bytes) -> None:
    """
    Save full message history for a session (overwrites).
    Pass result.all_messages_json() from the agent run.
    """
    row = db.query(ChatSession).filter(ChatSession.session_id == session_id).first()
    if not row:
        row = ChatSession(session_id=session_id)
        db.add(row)
    row.message_list = messages_json_bytes.decode("utf-8")
    row.updated_at = datetime.now(timezone.utc)
    db.commit()


def create_session_id() -> str:
    """Generate a new session id (UUID hex)."""
    return uuid.uuid4().hex


def list_recent_sessions(db: Session, limit: int = 20) -> list[dict]:
    """Return recent sessions (by updated_at, then id) for listing previous conversations."""
    rows = (
        db.query(ChatSession)
        .filter(ChatSession.message_list.isnot(None), ChatSession.message_list != "")
        .order_by(ChatSession.updated_at.desc().nulls_last(), ChatSession.id.desc())
        .limit(limit)
        .all()
    )
    return [
        {"session_id": r.session_id, "updated_at": r.updated_at.isoformat() if r.updated_at else None}
        for r in rows
    ]


def delete_session(db: Session, session_id: str) -> dict:
    """Delete one chat session by id. Returns {ok: true} or {error: ...}."""
    row = db.query(ChatSession).filter(ChatSession.session_id == session_id).first()
    if not row:
        return {"error": "Session not found."}
    db.delete(row)
    db.commit()
    return {"ok": True}


def delete_all_sessions(db: Session) -> dict:
    """Delete all chat sessions. Returns {ok: true, deleted: N}."""
    count = db.query(ChatSession).delete()
    db.commit()
    return {"ok": True, "deleted": count}


def save_last_venue_search(db: Session, session_id: str, venues: list[dict]) -> None:
    """Store last venue search for this session (for sidebar display and snapshot compare)."""
    row = db.query(ChatSession).filter(ChatSession.session_id == session_id).first()
    if not row:
        row = ChatSession(session_id=session_id)
        db.add(row)
    row.last_venue_search_json = json.dumps(venues)
    row.updated_at = datetime.now(timezone.utc)
    db.commit()


def get_last_venue_search(db: Session, session_id: str) -> list[dict] | None:
    """Return last venue search for this session, or None."""
    row = db.query(ChatSession).filter(ChatSession.session_id == session_id).first()
    if not row or not row.last_venue_search_json or not row.last_venue_search_json.strip():
        return None
    try:
        out = json.loads(row.last_venue_search_json)
        return out if isinstance(out, list) else None
    except (TypeError, json.JSONDecodeError):
        return None

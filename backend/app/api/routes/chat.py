"""
Chat endpoint: requests go to the orchestrator (Resy booking agent). Supports session memory.
"""
import json
import logging
from typing import NoReturn

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.errors import agent_error_to_http
from app.db.session import get_db
from app.orchestrator.orchestrator import run as orchestrator_run, run_stream as orchestrator_run_stream
from app.services.chat_session_service import (
    create_session_id,
    delete_all_sessions,
    delete_session,
    get_last_venue_search,
    get_messages,
    get_messages_for_display,
    list_recent_sessions,
    save_messages,
)
from app.services.resy import search_with_availability
from app.services.venue_notify_service import cancel_notify_request, get_my_watches, update_notify_request_title
from app.services.venue_watch_service import cancel_interval_watch, mark_notification_read
from app.services.resy_auto_book_service import get_recent_booking_attempts
from app.services.tool_call_log_service import get_recent_logs as get_tool_call_logs

router = APIRouter()
logger = logging.getLogger(__name__)


class ChatRequest(BaseModel):
    message: str
    session_id: str | None = None  # optional; if omitted, a new session is created


class UpdateNotifyTitleRequest(BaseModel):
    title: str


class ChatResponse(BaseModel):
    response: str
    session_id: str  # send this back on the next request for conversation context


def _handle_agent_error(exc: Exception, log_message: str) -> NoReturn:
    logger.exception(log_message)
    raise agent_error_to_http(exc) from exc


def _sse_line(obj: dict) -> bytes:
    """Single SSE event line as bytes so proxies/clients stream immediately."""
    return (f"data: {json.dumps(obj)}\n\n").encode("utf-8")


async def _stream_chat_sse(body: ChatRequest, db: Session):
    """Yield SSE events: data: {"content": "..."} for text, data: {"done": true, "session_id": "..."} at end."""
    session_id = body.session_id or create_session_id()
    try:
        message_history = get_messages(db, session_id)
    except Exception as e:
        logger.exception("Load messages failed")
        yield _sse_line({"error": str(e)})
        return
    try:
        async for kind, payload in orchestrator_run_stream(
            body.message, db, message_history=message_history, session_id=session_id
        ):
            if kind == "text":
                yield _sse_line({"content": payload})
            elif kind == "venues":
                yield _sse_line({"venues": payload})
            elif kind == "result":
                if payload is not None:
                    save_messages(db, session_id, payload.all_messages_json())
                yield _sse_line({"done": True, "session_id": session_id})
                return
            elif kind == "error":
                yield _sse_line({"error": str(payload)})
                return
    except Exception as e:
        logger.exception("Chat stream failed")
        yield _sse_line({"error": str(e)})


@router.post("", response_model=ChatResponse)
async def chat(
    body: ChatRequest,
    db: Session = Depends(get_db),
) -> ChatResponse:
    """
    Send a message; the orchestrator routes to the Resy booking agent.
    Pass session_id from a previous response to keep conversation context (session memory).
    """
    try:
        session_id = body.session_id or create_session_id()
        message_history = get_messages(db, session_id)
        text, result = await orchestrator_run(
            body.message, db, message_history=message_history, session_id=session_id
        )
        if result is not None:
            save_messages(db, session_id, result.all_messages_json())
        return ChatResponse(response=text, session_id=session_id)
    except Exception as e:  # noqa: BLE001
        _handle_agent_error(e, "Chat failed")


@router.post("/stream")
async def chat_stream(
    body: ChatRequest,
    db: Session = Depends(get_db),
):
    """Stream agent response as SSE. Events: data: {"content": "..."} then data: {"done": true, "session_id": "..."}."""
    return StreamingResponse(
        _stream_chat_sse(body, db),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/sessions")
async def list_sessions(limit: int = 20, db: Session = Depends(get_db)):
    """List recent sessions (with saved messages) for previous conversations."""
    try:
        return {"sessions": list_recent_sessions(db, limit=min(limit, 50))}
    except Exception as e:
        logger.warning("list_sessions failed: %s", e, exc_info=True)
        return {"sessions": []}


@router.delete("/sessions/all")
async def clear_all_sessions(db: Session = Depends(get_db)):
    """Delete all chat sessions (clear old chats)."""
    return delete_all_sessions(db)


@router.delete("/sessions/{session_id}")
async def remove_session(session_id: str, db: Session = Depends(get_db)):
    """Delete one chat session by id."""
    return delete_session(db, session_id)


@router.get("/messages")
async def list_messages(session_id: str, db: Session = Depends(get_db)):
    """Return message history for this session as [{ role, content }, ...] for display after refresh."""
    try:
        return {"messages": get_messages_for_display(db, session_id)}
    except Exception as e:
        logger.warning("list_messages failed: %s", e, exc_info=True)
        return {"messages": []}


@router.get("/venues")
async def get_venues(session_id: str, db: Session = Depends(get_db)):
    """Return last venue search for this session (same data as Real-time Inventory sidebar / snapshot)."""
    try:
        venues = get_last_venue_search(db, session_id)
        return {"venues": venues if venues else []}
    except Exception as e:
        logger.warning("get_venues failed: %s", e, exc_info=True)
        return {"venues": []}


@router.get("/watches")
async def list_watches(db: Session = Depends(get_db)):
    """List all active jobs (global across chat sessions): interval watches + notify requests + notifications."""
    try:
        return get_my_watches(db)
    except Exception as e:
        logger.warning("list_watches failed (run migrations?): %s", e, exc_info=True)
        return {"interval_watches": [], "notify_requests": [], "notifications": []}


@router.get("/watches/availability")
async def get_availability(date_str: str, party_size: int = 2, time_filter: str | None = None):
    """Current venues with availability for this date/party_size/time. Used to show live availability (e.g. in notification expanded view)."""
    from datetime import date
    try:
        day = date.fromisoformat(date_str)
    except ValueError:
        return {"error": "Invalid date. Use YYYY-MM-DD.", "venues": []}
    result = search_with_availability(day, party_size, time_filter=time_filter or None)
    if "error" in result:
        return {"error": result["error"], "venues": []}
    return {"venues": result.get("venues") or []}


@router.delete("/watches/interval/{watch_id}")
async def delete_interval_watch(watch_id: int, db: Session = Depends(get_db)):
    """Cancel an interval watch."""
    return cancel_interval_watch(db, watch_id)


@router.patch("/watches/notify/{request_id}")
async def patch_notify_request(
    request_id: int,
    body: UpdateNotifyTitleRequest,
    db: Session = Depends(get_db),
):
    """Update the title of a notify-when-available request."""
    return update_notify_request_title(db, request_id, body.title)


@router.delete("/watches/notify/{request_id}")
async def delete_notify_request(request_id: int, db: Session = Depends(get_db)):
    """Cancel a notify-when-available request."""
    return cancel_notify_request(db, request_id)


@router.post("/watches/notifications/{notification_id}/read")
async def read_notification(notification_id: int, db: Session = Depends(get_db)):
    """Mark a new-venues notification as read."""
    return mark_notification_read(db, notification_id)


@router.get("/booking-errors")
async def list_booking_errors(limit: int = 100, db: Session = Depends(get_db)):
    """List recent auto-booking attempts (success and failed)."""
    return {"attempts": get_recent_booking_attempts(db, limit=min(limit, 200))}


@router.get("/logs")
async def list_logs(limit: int = 100, db: Session = Depends(get_db)):
    """List recent tool call log entries for the Log tab (tool name + arguments). Merged with booking attempts for a single timeline."""
    try:
        tool_logs = get_tool_call_logs(db, limit=min(limit, 200))
    except Exception as e:
        logger.warning("get_tool_call_logs failed (run migrations?): %s", e, exc_info=True)
        tool_logs = []
    try:
        attempts = get_recent_booking_attempts(db, limit=min(limit, 200))
    except Exception as e:
        logger.warning("get_recent_booking_attempts failed: %s", e, exc_info=True)
        attempts = []
    entries = []
    for e in tool_logs:
        entries.append({"type": "tool_call", **e})
    for a in attempts:
        entries.append({
            "type": "booking_attempt",
            "id": a.get("id"),
            "created_at": a.get("created_at"),
            "tool_name": "book_venue",
            "arguments": {
                "venue_name": a.get("venue_name"),
                "date_str": a.get("date_str"),
                "party_size": a.get("party_size"),
            },
            "result_status": a.get("status"),
            "result_summary": a.get("error_message") if a.get("status") == "failed" else "Booked",
        })
    entries.sort(key=lambda x: x.get("created_at") or "", reverse=True)
    return {"entries": entries[: min(limit, 200)]}

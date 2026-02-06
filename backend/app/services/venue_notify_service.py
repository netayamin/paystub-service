"""
Notify when a specific venue has availability. Scheduler runs until status=notified.
"""
import json
from datetime import date, datetime, timezone

from sqlalchemy.orm import Session

from app.data.infatuation_hard_to_get import get_hard_to_get_list
from app.models.venue_notify_request import VenueNotifyRequest
from app.services.resy import search_with_availability


def start_venue_notify(
    db: Session,
    session_id: str,
    venue_name: str,
    date_str: str,
    party_size: int = 2,
    time_filter: str | None = None,
    title: str | None = None,
) -> dict:
    """Register: notify when this venue has availability. Returns {ok: true, id: ...} or error.
    Title is optional; when not provided, defaults to '{party_size} - {date_str} - {time_filter or any}'.
    Availability is checked over a ±1 hour window when time_filter is set."""
    venue_name = (venue_name or "").strip()
    if not venue_name:
        return {"error": "venue_name is required."}
    try:
        date.fromisoformat(date_str)
    except ValueError:
        return {"error": f"Invalid date {date_str}. Use YYYY-MM-DD."}
    title_val = (title or "").strip() or None
    if not title_val:
        title_val = f"{party_size} - {date_str} - {time_filter or 'any'}"
    row = VenueNotifyRequest(
        session_id=session_id,
        title=title_val,
        venue_name=venue_name,
        date_str=date_str,
        party_size=party_size,
        time_filter=time_filter,
        status="pending",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return {"ok": True, "id": row.id}


def start_notify_for_all_infatuation(
    db: Session,
    session_id: str,
    date_str: str,
    party_size: int = 2,
    time_filter: str | None = None,
    title_prefix: str | None = None,
) -> dict:
    """Create a notify request for every venue in the Infatuation hard-to-get list. Returns {ok: true, created: N, ids: [...]} or error. Use when the user says 'notify me for all of them'."""
    try:
        date.fromisoformat(date_str)
    except ValueError:
        return {"error": f"Invalid date {date_str}. Use YYYY-MM-DD."}
    venues = get_hard_to_get_list()
    prefix = (title_prefix or "Infatuation").strip() or "Infatuation"
    rows: list[VenueNotifyRequest] = []
    for v in venues:
        name = (v.get("name") or "").strip()
        if not name:
            continue
        title_val = f"{prefix}: {name}"
        resy_id = v.get("resy_venue_id") if isinstance(v.get("resy_venue_id"), int) else None
        row = VenueNotifyRequest(
            session_id=session_id,
            title=title_val,
            venue_name=name,
            date_str=date_str,
            party_size=party_size,
            time_filter=time_filter,
            status="pending",
            resy_venue_id=resy_id,
        )
        db.add(row)
        rows.append(row)
    db.commit()
    for row in rows:
        db.refresh(row)
    created_ids = [r.id for r in rows]
    return {"ok": True, "created": len(created_ids), "ids": created_ids, "total_venues": len(venues)}


def run_venue_notify_checks(db: Session) -> None:
    """Called by scheduler every 1 min. For each pending request, search (with ±1 hour window when time_filter set) and set notified if venue in results. Sets last_checked_at every run; when found, stores availability_times in result_json. Triggers auto-book in background for each newly notified venue."""
    import threading

    from app.services.resy_auto_book_service import run_auto_book_and_record

    now = datetime.now(timezone.utc)
    rows = db.query(VenueNotifyRequest).filter(VenueNotifyRequest.status == "pending").all()
    to_auto_book: list[tuple[str, str, int]] = []
    for row in rows:
        row.last_checked_at = now
        try:
            day = date.fromisoformat(row.date_str)
            raw = search_with_availability(
                day, row.party_size, time_filter=row.time_filter
            )
            if raw.get("error"):
                continue
            venues = raw.get("venues") or []
            for v in venues:
                match = False
                if row.resy_venue_id is not None:
                    match = v.get("venue_id") == row.resy_venue_id
                if not match:
                    match = (v.get("name") or "").strip() == row.venue_name
                if match:
                    row.status = "notified"
                    times = v.get("availability_times") or []
                    row.result_json = json.dumps({
                        "available": True,
                        "venue_name": row.venue_name,
                        "availability_times": times,
                    })
                    to_auto_book.append((row.venue_name, row.date_str, row.party_size))
                    break
        except Exception:
            continue
    db.commit()

    for venue_name, date_str, party_size in to_auto_book:
        thread = threading.Thread(
            target=run_auto_book_and_record,
            args=(venue_name, date_str, party_size),
            daemon=True,
        )
        thread.start()


def get_notify_requests(db: Session) -> list[dict]:
    """List all notify requests (active jobs are global, not per chat session)."""
    rows = (
        db.query(VenueNotifyRequest)
        .order_by(VenueNotifyRequest.created_at.desc())
        .all()
    )
    out = []
    for r in rows:
        found_times = None
        if r.result_json and r.status == "notified":
            try:
                data = json.loads(r.result_json)
                found_times = data.get("availability_times") or None
            except (TypeError, json.JSONDecodeError):
                pass
        out.append({
            "id": r.id,
            "type": "notify",
            "title": r.title,
            "venue_name": r.venue_name,
            "resy_venue_id": r.resy_venue_id,
            "date_str": r.date_str,
            "party_size": r.party_size,
            "time_filter": r.time_filter,
            "status": r.status,
            "result_json": r.result_json,
            "found_times": found_times,
            "last_checked_at": r.last_checked_at.isoformat() if r.last_checked_at else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })
    return out


def update_notify_request_title(db: Session, request_id: int, title: str) -> dict:
    """Update the title of an existing notify request. Returns {ok: true} or {error: ...}."""
    row = db.query(VenueNotifyRequest).filter(VenueNotifyRequest.id == request_id).first()
    if not row:
        return {"error": "Notify request not found."}
    row.title = (title or "").strip() or None
    db.commit()
    return {"ok": True, "id": row.id, "title": row.title}


def cancel_notify_request(db: Session, request_id: int) -> dict:
    """Remove a notify request. Returns {ok: true} or {error: ...}."""
    row = db.query(VenueNotifyRequest).filter(VenueNotifyRequest.id == request_id).first()
    if not row:
        return {"error": "Notify request not found."}
    db.delete(row)
    db.commit()
    return {"ok": True}


def get_my_watches(db: Session) -> dict:
    """Return all active jobs (global across chat sessions): interval watches + notify requests + notifications."""
    from app.services.venue_watch_service import get_interval_watches, get_notifications

    return {
        "interval_watches": get_interval_watches(db),
        "notify_requests": get_notify_requests(db),
        "notifications": get_notifications(db),
    }

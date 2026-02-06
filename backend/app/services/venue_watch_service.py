"""
Background watch: two separate features (separation of concerns).

1. Specific-venues watch: user provides a list of restaurant names; every N minutes we
   query Resy by name (query=<name>) for each; notify when any of those venues have
   availability (real-time inventory for known venues).

2. New-venues watch: user sets criteria (date, party_size, time_filter, optional query);
   every N minutes we run a broad search and diff vs last snapshot; notify only when
   new restaurant names appear in results (discovery).

Scheduler runs run_watch_checks() every minute; dispatches to the right path per watch.
"""
import json
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.venue_watch import VenueWatch
from app.models.venue_watch_notification import VenueWatchNotification
from app.services.resy_auto_book_service import VENUE_URL_TEMPLATE, _venue_name_to_slug
from app.services.tool_call_log_service import log_tool_call as log_tool_call_service
from app.services.venue_snapshot_service import (
    _criteria_key,
    check_for_new_venues,
    check_specific_venues_availability,
)

ALLOWED_INTERVAL_MINUTES = (1, 2, 5, 10)


def _watch_key(date_str: str, party_size: int, query: str, time_filter: str | None, interval_minutes: int) -> str:
    """Unique key per (criteria, interval) so multiple intervals can run for the same date/party/time."""
    base = _criteria_key(date_str, party_size, query, time_filter)
    return f"{base}|{interval_minutes}"


def _parse_watch_key(criteria_key: str) -> tuple[str, int, str, str | None]:
    """Parse criteria_key into (date_str, party_size, query, time_filter). Handles keys with optional trailing |interval."""
    parts = criteria_key.split("|")
    date_str = parts[0] if len(parts) > 0 else ""
    party_size = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 2
    query = parts[2] if len(parts) > 2 else ""
    time_filter = (parts[3] if len(parts) > 3 else "") or None
    return (date_str, party_size, query, time_filter)


def start_watch(
    db: Session,
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str | None = None,
    interval_minutes: int = 2,
    session_id: str | None = None,
    venue_names: list[str] | None = None,
) -> dict:
    """Register a watch for this criteria and interval. interval_minutes must be 1, 2, 5, or 10.
    If venue_names is provided, only new availability for those venues triggers a notification (same job as check-every-N)."""
    if interval_minutes not in ALLOWED_INTERVAL_MINUTES:
        return {"error": "interval_minutes must be 1, 2, 5, or 10."}
    key = _watch_key(date_str, party_size, query, time_filter, interval_minutes)
    q = db.query(VenueWatch).filter(VenueWatch.criteria_key == key)
    if session_id is not None:
        q = q.filter(VenueWatch.session_id == session_id)
    else:
        q = q.filter(VenueWatch.session_id.is_(None))
    row = q.first()
    if not row:
        row = VenueWatch(criteria_key=key, interval_minutes=interval_minutes, session_id=session_id)
        db.add(row)
    if venue_names is not None:
        row.venue_names_json = json.dumps([n.strip() for n in venue_names if n and n.strip()]) if venue_names else None
    db.commit()
    return {"ok": True, "interval_minutes": interval_minutes, "venue_count": len(venue_names) if venue_names else None}


def get_watch_update(
    db: Session,
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str | None = None,
    session_id: str | None = None,
) -> dict:
    """Return last check result for this criteria: {n: 0} or {n: N, new: [...]} or {pending: true} if not run yet. Matches any interval for this criteria."""
    base_key = _criteria_key(date_str, party_size, query, time_filter)
    q = db.query(VenueWatch).filter(
        (VenueWatch.criteria_key == base_key) | (VenueWatch.criteria_key.startswith(base_key + "|"))
    )
    if session_id is not None:
        q = q.filter(VenueWatch.session_id == session_id)
    else:
        q = q.filter(VenueWatch.session_id.is_(None))
    row = q.first()
    if not row:
        return {"error": "No watch for this date/party_size. Say 'check every 2 min' first."}
    if not row.last_result_json:
        return {"pending": True, "message": "First check not run yet. Ask again in a minute."}
    try:
        return json.loads(row.last_result_json)
    except (TypeError, json.JSONDecodeError):
        return {"pending": True}


def run_watch_checks(db: Session) -> None:
    """Called by scheduler every 1 min. Run check_for_new_venues for each watch that is due."""
    now = datetime.now(timezone.utc)
    rows = db.query(VenueWatch).all()
    watches_checked = 0
    notifications_created = 0
    for row in rows:
        due = False
        if row.last_checked_at is None:
            due = True
        else:
            last = row.last_checked_at
            if last.tzinfo is None:
                last = last.replace(tzinfo=timezone.utc)
            if last + timedelta(minutes=row.interval_minutes) <= now:
                due = True
        if not due:
            continue
        watches_checked += 1
        date_str, party_size, query, time_filter = _parse_watch_key(row.criteria_key)
        try:
            watch_venue_names: list[str] | None = None
            if row.venue_names_json:
                try:
                    watch_venue_names = json.loads(row.venue_names_json)
                except (TypeError, json.JSONDecodeError):
                    watch_venue_names = []
            has_specific_list = bool(watch_venue_names and [n for n in watch_venue_names if (n or "").strip()])

            if has_specific_list:
                # Feature 1: specific-venues watch — query by name per venue; notify on availability.
                result = check_specific_venues_availability(
                    db, date_str, party_size, time_filter=time_filter, venue_names=watch_venue_names or []
                )
            else:
                # Feature 2: new-venues watch — broad search; notify when new names appear.
                result = check_for_new_venues(
                    db, date_str, party_size, query=query, time_filter=time_filter
                )

            if "error" not in result:
                if result.get("baseline"):
                    if has_specific_list:
                        row.last_result_json = json.dumps(
                            {"baseline": True, "current_available": result.get("current_available", [])}
                        )
                    else:
                        row.last_result_json = json.dumps({"baseline": True, "total": result.get("total", 0)})
                    # On first run for specific-venues: notify for any that are available now.
                    if has_specific_list and row.session_id:
                        current_available = result.get("current_available") or []
                        if current_available:
                            summary = _criteria_summary(date_str, party_size, time_filter)
                            notif = VenueWatchNotification(
                                session_id=row.session_id,
                                criteria_summary=summary,
                                date_str=date_str,
                                party_size=party_size,
                                time_filter=time_filter,
                                new_count=len(current_available),
                                new_names_json=json.dumps(current_available),
                            )
                            db.add(notif)
                            notifications_created += 1
                else:
                    row.last_result_json = json.dumps(result)
                    if result.get("n", 0) > 0 and row.session_id and "new" in result:
                        summary = _criteria_summary(date_str, party_size, time_filter)
                        notif = VenueWatchNotification(
                            session_id=row.session_id,
                            criteria_summary=summary,
                            date_str=date_str,
                            party_size=party_size,
                            time_filter=time_filter,
                            new_count=result["n"],
                            new_names_json=json.dumps(result["new"]),
                        )
                        db.add(notif)
                        notifications_created += 1
        except Exception:
            pass
        row.last_checked_at = now
    db.commit()
    if watches_checked > 0:
        try:
            log_tool_call_service(
                db,
                "run_watch_checks",
                {
                    "run_at": now.isoformat(),
                    "watches_checked": watches_checked,
                    "notifications_created": notifications_created,
                    "total_watches": len(rows),
                },
                session_id=None,
            )
        except Exception:
            pass


def _criteria_summary(date_str: str, party_size: int, time_filter: str | None) -> str:
    """Summary for notifications: date · time (or time ±1h) · party size. Search uses ±1 hour around time_filter."""
    parts = [date_str]
    if time_filter and (tf := time_filter.strip()):
        parts.append(f"{tf} ±1h")
    else:
        parts.append("any time")
    parts.append(f"{party_size} people")
    return " · ".join(parts)


def get_interval_watches(db: Session) -> list[dict]:
    """List all interval watches (active jobs are global, not per chat session)."""
    rows = db.query(VenueWatch).order_by(VenueWatch.created_at.desc()).all()
    out = []
    for r in rows:
        date_str, party_size, query, time_filter = _parse_watch_key(r.criteria_key)
        venue_names = None
        if r.venue_names_json:
            try:
                venue_names = json.loads(r.venue_names_json)
            except (TypeError, json.JSONDecodeError):
                venue_names = []
        out.append({
            "id": r.id,
            "type": "interval",
            "date_str": date_str,
            "party_size": party_size,
            "query": query,
            "time_filter": time_filter,
            "interval_minutes": r.interval_minutes,
            "venue_names": venue_names,
            "last_checked_at": r.last_checked_at.isoformat() if r.last_checked_at else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })
    return out


def _resy_venue_url(venue_name: str, date_str: str, party_size: int) -> str | None:
    """Build Resy venue page URL for booking. Returns None if slug is invalid."""
    slug = _venue_name_to_slug(venue_name)
    if not slug:
        return None
    return VENUE_URL_TEMPLATE.format(slug=slug, date=date_str, seats=party_size)


def get_notifications(db: Session) -> list[dict]:
    """List all notifications (new venues found); active jobs are global.
    Each notification includes new_venues: [{ name, resy_url }] for BOOK NOW links.
    """
    rows = (
        db.query(VenueWatchNotification)
        .order_by(VenueWatchNotification.created_at.desc())
        .limit(50)
        .all()
    )
    out = []
    for r in rows:
        try:
            names = json.loads(r.new_names_json) if r.new_names_json else []
        except (TypeError, json.JSONDecodeError):
            names = []
        new_venues = [
            {
                "name": name,
                "resy_url": _resy_venue_url(name, r.date_str, r.party_size),
            }
            for name in names
        ]
        out.append({
            "id": r.id,
            "criteria_summary": r.criteria_summary,
            "date_str": r.date_str,
            "party_size": r.party_size,
            "time_filter": r.time_filter,
            "new_count": r.new_count,
            "new_names": names,
            "new_venues": new_venues,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })
    return out


def mark_notification_read(db: Session, notification_id: int) -> dict:
    """Mark as read by removing the notification from the table (we don't keep read ones)."""
    row = db.query(VenueWatchNotification).filter(VenueWatchNotification.id == notification_id).first()
    if not row:
        return {"error": "Notification not found."}
    db.delete(row)
    db.commit()
    return {"ok": True}


def cancel_interval_watch(db: Session, watch_id: int) -> dict:
    """Remove an interval watch. Returns {ok: true} or {error: ...}."""
    row = db.query(VenueWatch).filter(VenueWatch.id == watch_id).first()
    if not row:
        return {"error": "Watch not found."}
    db.delete(row)
    db.commit()
    return {"ok": True}

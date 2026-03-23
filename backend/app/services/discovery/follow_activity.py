"""Follow list status and lightweight activity timeline (Phase 7.1)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.hotspots import list_hotspots
from app.models.drop_event import DropEvent
from app.models.notify_preference import NotifyPreference
from app.models.user_notification import UserNotification


def _norm(s: str | None) -> str:
    return (s or "").strip().lower()


def last_drop_at_by_normalized_venue_name(db: Session, normalized_names: list[str]) -> dict[str, datetime]:
    """Latest DropEvent.user_facing_opened_at per normalized venue_name (trimmed, lower)."""
    names = [_norm(n) for n in normalized_names if _norm(n)]
    if not names:
        return {}
    vn = func.lower(func.trim(DropEvent.venue_name))
    rows = (
        db.query(vn.label("k"), func.max(DropEvent.user_facing_opened_at))
        .filter(DropEvent.venue_name.isnot(None))
        .filter(vn.in_(names))
        .group_by(vn)
        .all()
    )
    out: dict[str, datetime] = {}
    for k, mx in rows:
        if k and mx:
            out[str(k)] = mx if mx.tzinfo else mx.replace(tzinfo=timezone.utc)
    return out


def follow_status_for_recipient(
    db: Session,
    recipient_id: str,
    *,
    recent_within_hours: float = 48.0,
    market: str = "nyc",
) -> dict:
    """
    Per venue on the effective notify list (hotlist ∪ saved includes) − excludes:
    last observed drop time (from drop_events) and recent flag.
    """
    rid = (recipient_id or "default").strip() or "default"
    includes = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.preference == "include")
        .order_by(NotifyPreference.id.asc())
        .all()
    )
    excludes = {
        r.venue_name_normalized
        for r in db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.preference == "exclude")
        .all()
    }
    mkt = (market or "nyc").strip().lower()
    entries: list[tuple[str, int | None, bool]] = []
    seen: set[str] = set()
    for row in includes:
        n = row.venue_name_normalized
        if n in excludes or n in seen:
            continue
        seen.add(n)
        entries.append((n, row.id, True))
    try:
        hot = list_hotspots(mkt)
    except Exception:
        hot = list_hotspots("nyc")
    for name in hot:
        n = _norm(name)
        if not n or n in excludes or n in seen:
            continue
        seen.add(n)
        entries.append((n, None, False))

    norms = [e[0] for e in entries]
    last_map = last_drop_at_by_normalized_venue_name(db, norms)
    now = datetime.now(timezone.utc)
    window = timedelta(hours=recent_within_hours)
    follows = []
    for n, wid, saved in entries:
        ts = last_map.get(n)
        follows.append(
            {
                "watch_id": wid,
                "venue_name": n,
                "from_saved_list": saved,
                "last_drop_at": ts.isoformat() if ts else None,
                "recent_activity": bool(ts and (now - ts) <= window),
            }
        )
    return {"recipient_id": rid, "market": mkt, "follows": follows}


def follow_activity_timeline(db: Session, recipient_id: str, *, limit: int = 40) -> dict:
    """
    Simple activity stream from persisted user_notifications (type new_drop).
    Caught/missed is represented implicitly: rows exist when the client (or server) recorded them.
    """
    rid = (recipient_id or "default").strip() or "default"
    lim = max(1, min(200, int(limit)))
    rows = (
        db.query(UserNotification)
        .filter(UserNotification.recipient_id == rid, UserNotification.type == "new_drop")
        .order_by(UserNotification.created_at.desc())
        .limit(lim)
        .all()
    )
    items = []
    for r in rows:
        meta = r.payload if isinstance(r.payload, dict) else {}
        items.append(
            {
                "id": r.id,
                "kind": "in_app",
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "read": r.read_at is not None,
                "venue_name": meta.get("name") or meta.get("venue_name"),
                "date_str": meta.get("date_str"),
                "resy_url": meta.get("resy_url") or meta.get("resyUrl"),
            }
        )
    return {"recipient_id": rid, "items": items}

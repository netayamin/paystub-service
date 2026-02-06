"""
Stores and diffs venue search results by criteria.

Two distinct features (separation of concerns):
1. New-venues watch: broad search by (date, party_size, query, time_filter); diff vs last
   snapshot and report when new restaurant names appear in results (discovery).
2. Specific-venues watch: for a list of restaurant names, query Resy by name (query=name)
   once per venue; report when any of those venues have availability (real-time inventory).
"""
import hashlib
import json
from datetime import date

from sqlalchemy.orm import Session

from app.models.venue_search_snapshot import VenueSearchSnapshot
from app.services.resy import search_with_availability


def _criteria_key(date_str: str, party_size: int, query: str, time_filter: str | None) -> str:
    return "|".join([date_str, str(party_size), query or "", (time_filter or "").strip()])


def _specific_criteria_key(
    date_str: str, party_size: int, time_filter: str | None, venue_names: list[str]
) -> str:
    """Stable key for specific-venue snapshot; uses hash to stay under 256 chars."""
    base = _criteria_key(date_str, party_size, "", time_filter)
    normalized = "|".join(sorted((n or "").strip().lower() for n in venue_names if (n or "").strip()))
    digest = hashlib.sha256(normalized.encode()).hexdigest()[:32]
    return f"{base}|specific|{digest}"


def _get_snapshot(db: Session, key: str) -> list[str]:
    row = db.query(VenueSearchSnapshot).filter(VenueSearchSnapshot.criteria_key == key).first()
    if not row or not row.venue_names_json:
        return []
    try:
        return json.loads(row.venue_names_json)
    except (TypeError, json.JSONDecodeError):
        return []


def _save_snapshot(db: Session, key: str, names: list[str]) -> None:
    row = db.query(VenueSearchSnapshot).filter(VenueSearchSnapshot.criteria_key == key).first()
    if not row:
        row = VenueSearchSnapshot(criteria_key=key)
        db.add(row)
    row.venue_names_json = json.dumps(names)
    db.commit()


def save_broad_search_snapshot(
    db: Session,
    date_str: str,
    party_size: int,
    query: str = "",
    time_filter: str | None = None,
    names: list[str] | None = None,
) -> None:
    """Save venue names for this criteria so check_for_new_venues can diff. Call after search_venues_with_availability."""
    key = _criteria_key(date_str, party_size, query or "", (time_filter or "").strip())
    _save_snapshot(db, key, names or [])


def check_for_new_venues(
    db: Session,
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str | None = None,
) -> dict:
    """
    Run search for (date_str, party_size, query, time_filter), compare to last saved snapshot.
    Returns minimal payload for agent: {baseline: true, total: N} on first run,
    else {n: new_count, new: [names]} or {n: 0}. Saves current names as new snapshot.
    """
    key = _criteria_key(date_str, party_size, query, time_filter)
    try:
        day = date.fromisoformat(date_str)
    except ValueError:
        return {"error": f"Invalid date {date_str}. Use YYYY-MM-DD."}
    raw = search_with_availability(day, party_size, query=query, time_filter=time_filter)
    if raw.get("error"):
        return raw
    current_names = [v.get("name") or "" for v in raw.get("venues") or []]
    previous = _get_snapshot(db, key)
    _save_snapshot(db, key, current_names)
    if not previous:
        return {"baseline": True, "total": len(current_names), "current": current_names}
    prev_set = set(previous)
    curr_set = set(current_names)
    new = sorted(curr_set - prev_set)
    return {"n": len(new), "new": new}


def check_specific_venues_availability(
    db: Session,
    date_str: str,
    party_size: int = 2,
    time_filter: str | None = None,
    venue_names: list[str] | None = None,
) -> dict:
    """
    For each venue name, run a Resy search with query=<name> (per_page=20, 1 page).
    The first result is that restaurant; if it has availability, count it as available.
    Compare to last snapshot; return baseline or newly_available.
    """
    if not venue_names or not [n for n in venue_names if (n or "").strip()]:
        return {"error": "venue_names must be a non-empty list of restaurant names."}
    try:
        day = date.fromisoformat(date_str)
    except ValueError:
        return {"error": f"Invalid date {date_str}. Use YYYY-MM-DD."}
    key = _specific_criteria_key(date_str, party_size, time_filter, venue_names)
    current_available: list[str] = []
    for name in venue_names:
        q = (name or "").strip()
        if not q:
            continue
        raw = search_with_availability(
            day, party_size, query=q, time_filter=time_filter, per_page=20, max_pages=1
        )
        if raw.get("error"):
            continue
        venues = raw.get("venues") or []
        if venues:
            # First hit is the restaurant matching the query; use its canonical name
            current_available.append((venues[0].get("name") or q).strip() or q)
    previous = _get_snapshot(db, key)
    _save_snapshot(db, key, current_available)
    if not previous:
        return {"baseline": True, "current_available": current_available}
    newly = sorted(set(current_available) - set(previous))
    return {"n": len(newly), "new": newly, "current_available": current_available}

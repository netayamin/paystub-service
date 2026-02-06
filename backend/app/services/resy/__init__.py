"""Resy API client: venue search. Validation here; client below just sends the request."""
import re
from datetime import date
from typing import Any

from app.services.resy.client import ResyClient
from app.services.resy.config import ResyConfig

default_client = ResyClient()


def _time_filter_to_hour(time_filter: str) -> int | None:
    """Parse time_filter (e.g. 21:00, 21:30, 9) to hour 0-23. Returns None if invalid."""
    s = (time_filter or "").strip()
    if not s:
        return None
    m = re.match(r"^(\d{1,2})(?::(\d{2}))?$", s)
    if m:
        h = int(m.group(1))
        if 0 <= h <= 23:
            return h
    return None


def _time_filter_window(time_filter: str) -> list[str]:
    """Given a time like 21:00 (9pm), return [20:00, 21:00, 22:00] for ±1 hour."""
    hour = _time_filter_to_hour(time_filter)
    if hour is None:
        return [time_filter.strip()] if time_filter else []
    return [f"{(hour - 1) % 24:02d}:00", f"{hour:02d}:00", f"{(hour + 1) % 24:02d}:00"]


def _venue_key(hit: dict[str, Any]) -> str:
    """Unique key for merging hits (same venue)."""
    vid = (hit.get("venue") or {}).get("id") or hit.get("id")
    if vid is not None:
        return f"id:{vid}"
    name = hit.get("name") or (hit.get("venue") or {}).get("name") or ""
    return f"name:{name}"


def _merge_hits_by_venue(hits_list: list[list[dict[str, Any]]]) -> list[dict[str, Any]]:
    """Merge multiple hit lists by venue key; combine availability.slots (dedupe by start time)."""
    by_key: dict[str, dict[str, Any]] = {}
    for hits in hits_list:
        for h in hits:
            key = _venue_key(h)
            slots = (h.get("availability") or {}).get("slots") or []
            if key not in by_key:
                by_key[key] = {**h, "availability": {"slots": list(slots)}}
            else:
                existing = by_key[key].setdefault("availability", {}).setdefault("slots", [])
                seen_starts = set()
                for s in existing:
                    start = (s.get("date") if isinstance(s, dict) else {}).get("start")
                    if start is not None:
                        seen_starts.add(start)
                for s in slots:
                    start = (s.get("date") if isinstance(s, dict) else {}).get("start")
                    if start is None or start not in seen_starts:
                        existing.append(s)
                        if start is not None:
                            seen_starts.add(start)
    return list(by_key.values())


def _day_to_iso(day: Any) -> str | None:
    """Return YYYY-MM-DD string or None if invalid."""
    if day is None:
        return None
    if isinstance(day, date):
        return day.isoformat()
    s = str(day).strip()
    if not s:
        return None
    try:
        return date.fromisoformat(s).isoformat()
    except ValueError:
        return None


def _extract_venue(hit: dict[str, Any]) -> dict[str, Any]:
    venue_obj = hit.get("venue") or {}
    name = hit.get("name") or venue_obj.get("name") or ""
    vid = venue_obj.get("id") or hit.get("id")
    neighborhood = hit.get("neighborhood") or (hit.get("location") or {}).get("neighborhood") or ""
    slots = (hit.get("availability") or {}).get("slots") or []
    availability_times = []
    for s in slots:
        date_obj = (s.get("date") if isinstance(s, dict) else None) or {}
        start = date_obj.get("start") if isinstance(date_obj, dict) else None
        if start:
            availability_times.append(start)
    out: dict[str, Any] = {"name": name, "neighborhood": neighborhood, "availability_times": availability_times}
    if vid is not None:
        out["venue_id"] = vid
    # Optional image URL when Resy API provides it (hero_image, image_url, etc.)
    image_url = (
        venue_obj.get("hero_image")
        or venue_obj.get("image_url")
        or hit.get("hero_image")
        or hit.get("image_url")
        or (isinstance(venue_obj.get("images"), list) and venue_obj["images"][0] if venue_obj.get("images") else None)
    )
    if image_url and isinstance(image_url, str):
        out["image_url"] = image_url
    return out


def _has_availability(hit: dict[str, Any]) -> bool:
    """True if the hit has at least one availability slot."""
    slots = (hit.get("availability") or {}).get("slots") or []
    return len(slots) > 0


def search_with_availability(
    day: Any,
    party_size: int = 2,
    *,
    query: str = "",
    per_page: int = 100,
    max_pages: int = 5,
    time_filter: str | None = None,
    venue_filter: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Search venues with availability; returns only venues that have at least one slot. Fetches all pages (using API total_pages), capped at max_pages (default 5 = up to 500 venues). Returns { venues: [...] } or { error: ... }."""
    day_str = _day_to_iso(day)
    if not day_str:
        return {"error": "Invalid or missing date. Use YYYY-MM-DD."}
    try:
        ps = int(party_size)
    except (TypeError, ValueError):
        return {"error": "party_size must be a number."}
    if ps < 1:
        return {"error": "party_size must be at least 1."}
    time_str = str(time_filter).strip() if time_filter else None
    if time_str:
        time_filters = _time_filter_window(time_str)
        all_hits_list: list[list[dict[str, Any]]] = []
        for t in time_filters:
            raw = default_client.search_with_availability(
                day_str,
                ps,
                query=query.strip(),
                per_page=per_page,
                max_pages=max_pages,
                time_filter=t,
                venue_filter=venue_filter,
            )
            if raw.get("error"):
                return raw
            hits = (raw.get("search") or {}).get("hits") or []
            all_hits_list.append(hits)
        hits = _merge_hits_by_venue(all_hits_list)
    else:
        raw = default_client.search_with_availability(
            day_str,
            ps,
            query=query.strip(),
            per_page=per_page,
            max_pages=max_pages,
            time_filter=None,
            venue_filter=venue_filter,
        )
        if raw.get("error"):
            return raw
        hits = (raw.get("search") or {}).get("hits") or []
    # Only include venues that have availability
    hits_with_availability = [h for h in hits if _has_availability(h)]
    return {"venues": [_extract_venue(h) for h in hits_with_availability]}


__all__ = ["ResyClient", "ResyConfig", "default_client", "search_with_availability"]

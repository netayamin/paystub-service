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


def _time_filter_window(time_filter: str, window_hours: int = 1) -> list[str]:
    """Given anchor time (e.g. 15:00 or 19:00), return that hour ± window_hours. window_hours=3 gives Resy's ±3h window."""
    hour = _time_filter_to_hour(time_filter)
    if hour is None:
        return [time_filter.strip()] if time_filter else []
    return [f"{(hour + h) % 24:02d}:00" for h in range(-window_hours, window_hours + 1)]


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


RESY_VENUE_BASE = "https://www.resy.com"


def _normalize_venue_id(vid: Any) -> str | int | None:
    """Resy API may return id as scalar or as dict e.g. {\"resy\": 60029}."""
    if vid is None:
        return None
    if isinstance(vid, dict):
        return vid.get("resy") or vid.get("id")
    return vid


def _build_resy_venue_url(
    venue_slug: str,
    location_slug: str,
    date_str: str,
    party_size: int,
) -> str:
    """Build Resy venue booking page URL. Format: /cities/{loc}/venues/{slug}?date=YYYY-MM-DD&seats=N."""
    loc = (location_slug or "new-york-ny").strip() or "new-york-ny"
    slug = venue_slug.strip()
    if not slug:
        return ""
    return f"{RESY_VENUE_BASE}/cities/{loc}/venues/{slug}?date={date_str}&seats={party_size}"


def _resy_popularity_score(rating_avg: float | None, rating_count: int | None, is_staff_pick: bool) -> float:
    """Score 0..1 for ranking: Resy rating, review count, and Staff Picks boost."""
    score = 0.5  # baseline
    if rating_avg is not None and isinstance(rating_avg, (int, float)):
        score += (float(rating_avg) - 3.0) / 4.0 * 0.35  # ~3->0.5, 4.6->0.64, 5->0.675
    if rating_count is not None and isinstance(rating_count, (int, float)):
        count = int(rating_count)
        score += min(count / 5000, 1.0) * 0.2  # cap at 5k reviews
    if is_staff_pick:
        score += 0.25
    return min(1.0, max(0.0, score))


def _extract_venue(
    hit: dict[str, Any],
    *,
    date_str: str | None = None,
    party_size: int = 2,
) -> dict[str, Any]:
    """Extract venue for discovery/just-opened. Builds resy_url from url_slug + location when date_str is set. Includes Resy rating and collections for popularity."""
    venue_obj = hit.get("venue") or {}
    name = hit.get("name") or venue_obj.get("name") or ""
    raw_id = venue_obj.get("id") or hit.get("id")
    vid = _normalize_venue_id(raw_id)
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
    # Optional image URL
    image_url = (
        hit.get("hero_image")
        or hit.get("image_url")
        or (hit.get("images") and isinstance(hit["images"], list) and len(hit["images"]) > 0 and hit["images"][0])
        or venue_obj.get("hero_image")
        or venue_obj.get("image_url")
        or (isinstance(venue_obj.get("images"), list) and venue_obj["images"][0] if venue_obj.get("images") else None)
    )
    if image_url and isinstance(image_url, str):
        out["image_url"] = image_url
    resy_slug = venue_obj.get("slug") or hit.get("slug") or venue_obj.get("url_slug") or hit.get("url_slug")
    if resy_slug and isinstance(resy_slug, str):
        out["resy_slug"] = resy_slug.strip()
    # Prefer explicit URL from API, else build from url_slug + location (Resy format: cities/{loc}/venues/{slug}?date=&seats=)
    resy_url = venue_obj.get("url") or hit.get("url") or venue_obj.get("resy_url") or hit.get("resy_url")
    if resy_url and isinstance(resy_url, str) and "resy.com" in resy_url:
        out["resy_url"] = resy_url.strip()
    elif date_str and resy_slug and isinstance(resy_slug, str):
        loc_slug = (hit.get("location") or {}).get("url_slug") or (venue_obj.get("location") or {}).get("url_slug") or "new-york-ny"
        built = _build_resy_venue_url(resy_slug, loc_slug, date_str, party_size)
        if built:
            out["resy_url"] = built
    # Resy search hit: rating and collections for popularity (search endpoint returns rating.average, rating.count, collections)
    rating = hit.get("rating") or venue_obj.get("rating")
    if isinstance(rating, dict):
        avg = rating.get("average")
        cnt = rating.get("count")
        if avg is not None:
            out["rating_average"] = float(avg) if isinstance(avg, (int, float)) else None
        if cnt is not None:
            out["rating_count"] = int(cnt) if isinstance(cnt, (int, float)) else None
    collections = hit.get("collections") or venue_obj.get("collections") or []
    if isinstance(collections, list) and collections:
        short_names = [c.get("short_name") or c.get("name") for c in collections if isinstance(c, dict) and (c.get("short_name") or c.get("name"))]
        if short_names:
            out["resy_collections"] = short_names
    is_staff_pick = (
        any(
            isinstance(c, dict)
            and ((c.get("short_name") or "").lower().find("staff") >= 0 or (c.get("name") or "").lower().find("staff") >= 0)
            for c in (collections if isinstance(collections, list) else [])
        )
        if isinstance(collections, list)
        else False
    )
    out["resy_popularity_score"] = _resy_popularity_score(
        out.get("rating_average"),
        out.get("rating_count"),
        is_staff_pick,
    )
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
    time_window_hours: int = 1,
    venue_filter: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Search venues with availability; returns only venues that have at least one slot. Fetches all pages (using API total_pages), capped at max_pages (default 5 = up to 500 venues). When time_filter is set, time_window_hours (default 1) expands to ±N hours; use 3 for Resy's natural ±3h window."""
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
        time_filters = _time_filter_window(time_str, window_hours=time_window_hours)
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
    # Only include venues that have availability; pass date and party_size so resy_url is built for the booking link
    hits_with_availability = [h for h in hits if _has_availability(h)]
    return {"venues": [_extract_venue(h, date_str=day_str, party_size=ps) for h in hits_with_availability]}


from app.services.resy.types import (
    ResyLocation,
    ResySearchHit,
    ResySlot,
    ResySlotConfig,
    ResySlotDate,
    ResyVenueExtract,
)

__all__ = [
    "ResyClient",
    "ResyConfig",
    "default_client",
    "search_with_availability",
    "ResyLocation",
    "ResySearchHit",
    "ResySlot",
    "ResySlotConfig",
    "ResySlotDate",
    "ResyVenueExtract",
]

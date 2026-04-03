"""
Explicit Resy venue states per design doc (query-universe truth, not marketing copy).

BOOKABLE: venue in response with ≥1 bookable slot.
UNBOOKABLE: venue in response with availability null or empty slots.
ABSENT: venue not in this poll's hit list (for union of known + present ids).
UNKNOWN: poll untrusted (e.g. low coverage).
"""
from __future__ import annotations

from typing import Any

BOOKABLE = "BOOKABLE"
UNBOOKABLE = "UNBOOKABLE"
ABSENT = "ABSENT"
UNKNOWN = "UNKNOWN"


def has_bookable_slots(hit: dict[str, Any]) -> bool:
    """Strict: at least one slot in availability.slots."""
    slots = (hit.get("availability") or {}).get("slots") or []
    return len(slots) > 0


def extract_state_from_hit(hit: dict[str, Any] | None) -> str:
    """
    Map one raw search hit to BOOKABLE / UNBOOKABLE / ABSENT.
    Call with None when venue missing from response → ABSENT.
    """
    if hit is None:
        return ABSENT
    avail = hit.get("availability")
    if avail is None:
        return UNBOOKABLE
    slots = (avail.get("slots") if isinstance(avail, dict) else None) or []
    if not slots:
        return UNBOOKABLE
    if has_bookable_slots(hit):
        return BOOKABLE
    return UNKNOWN


def _normalize_venue_id(raw: Any) -> str | int | None:
    if raw is None:
        return None
    if isinstance(raw, dict):
        return raw.get("resy") or raw.get("id")
    return raw


def venue_id_from_hit(hit: dict[str, Any]) -> str:
    """Stable string venue id for DB keys; empty if missing."""
    venue_obj = hit.get("venue") or {}
    raw_id = venue_obj.get("id") or hit.get("id")
    vid = _normalize_venue_id(raw_id)
    if vid is None:
        return ""
    return str(vid).strip()


def venue_name_from_hit(hit: dict[str, Any]) -> str:
    return (hit.get("name") or (hit.get("venue") or {}).get("name") or "").strip()

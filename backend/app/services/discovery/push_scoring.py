"""Heuristics for ordering push sends (Phase 7.3) — no user-facing analytics."""
from __future__ import annotations

from collections.abc import Callable


def push_delivery_score(
    venue_norm: str,
    venue_name: str | None,
    venue_id: str | None,
    eligibility_evidence: str | None,
    *,
    explicit_includes: set[str],
    rarity_by_venue_id: dict[str, float],
    is_hotspot_fn: Callable[[str | None], bool],
) -> float:
    """
    Higher = notify first. Uses only server-side facts: saved list, hotspot, rolling rarity,
    and diff strength (same family as feed eligibility).
    """
    score = 0.0
    if venue_norm and venue_norm in explicit_includes:
        score += 4.0
    if is_hotspot_fn(venue_name):
        score += 2.0
    ev = (eligibility_evidence or "").strip()
    if ev == "nonempty_prev_delta":
        score += 1.5
    elif ev == "empty_prev_delta":
        score += 0.8
    vid = (venue_id or "").strip()
    if vid:
        r = float(rarity_by_venue_id.get(vid) or 0.0)
        score += min(4.0, max(0.0, r) / 25.0)
    return score


def should_use_rare_opening_title(
    venue_norm: str,
    venue_name: str | None,
    venue_id: str | None,
    *,
    explicit_includes: set[str],
    rarity_by_venue_id: dict[str, float],
    is_hotspot_fn: Callable[[str | None], bool],
    rarity_threshold: float = 68.0,
) -> bool:
    """Plain-language urgency for APNs title — not a probability or percentage."""
    vid = (venue_id or "").strip()
    r = float(rarity_by_venue_id.get(vid) or 0.0) if vid else 0.0
    if r >= rarity_threshold:
        return True
    if venue_norm in explicit_includes and is_hotspot_fn(venue_name) and r >= 45.0:
        return True
    return False

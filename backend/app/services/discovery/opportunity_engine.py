"""
Stateful opportunity detection (Resy): explicit BOOKABLE / UNBOOKABLE / ABSENT / UNKNOWN,
STRONG_OPEN / WEAK_OPEN transitions, v1 scoring. Persists OpportunityPollRun, VenueBucketState, OpportunityEvent.
"""
from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.models.opportunity_event import OpportunityEvent
from app.models.opportunity_poll_run import OpportunityPollRun
from app.models.venue_bucket_state import VenueBucketState
from app.services.resy import _resy_popularity_score
from app.services.resy.venue_state import (
    ABSENT,
    BOOKABLE,
    UNKNOWN,
    UNBOOKABLE,
    extract_state_from_hit,
    venue_id_from_hit,
    venue_name_from_hit,
)

logger = logging.getLogger(__name__)

MIN_COVERAGE_SCORE = 0.8
MIN_CONSECUTIVE_UNBOOKABLE_FOR_STRONG_OPEN = 2
OPPORTUNITY_COOLDOWN_MINUTES = 15
WEAK_OPEN_MIN_OPPORTUNITY_SCORE = 0.82
WEAK_OPEN_MIN_VENUE_SCORE = 0.65


def compute_coverage_score(venue_hit_count: int, error_count: int) -> float:
    """v1: penalize errors; reward non-empty hit list."""
    if error_count >= 5:
        return 0.0
    if venue_hit_count <= 0:
        return 0.35
    base = 0.92 if error_count == 0 else 0.75 if error_count <= 2 else 0.55
    # Slightly lower if very small result set (possible partial failure)
    if venue_hit_count < 8:
        base *= 0.9
    return min(1.0, max(0.0, base))


def _rating_from_hit(hit: dict[str, Any]) -> tuple[float | None, int | None]:
    venue_obj = hit.get("venue") or {}
    rating = hit.get("rating") or venue_obj.get("rating")
    if not isinstance(rating, dict):
        return None, None
    avg = rating.get("average")
    cnt = rating.get("count")
    try:
        a = float(avg) if avg is not None else None
    except (TypeError, ValueError):
        a = None
    try:
        c = int(cnt) if cnt is not None else None
    except (TypeError, ValueError):
        c = None
    return a, c


def _venue_desirability_score(hit: dict[str, Any] | None) -> float:
    if not hit:
        return 0.4
    ra, rc = _rating_from_hit(hit)
    return _resy_popularity_score(ra, rc, False)


def _timing_score_v1(time_slot: str) -> float:
    """Prime dinner ~18–21 rough bump."""
    try:
        parts = (time_slot or "").split(":")
        h = int(parts[0]) if parts else 12
    except (ValueError, IndexError):
        return 0.55
    if 17 <= h <= 21:
        return 0.85
    if 11 <= h <= 16:
        return 0.5
    return 0.45


def compute_opportunity_scores_v1(
    event_type: str,
    hit: dict[str, Any] | None,
    coverage: float,
    prior_consecutive_unbookable: int,
    time_slot: str,
) -> dict[str, float]:
    venue_s = _venue_desirability_score(hit)
    scarcity_s = min(1.0, prior_consecutive_unbookable / 5.0)
    timing_s = _timing_score_v1(time_slot)
    ttl_s = 0.55
    conf_s = coverage * min(1.0, prior_consecutive_unbookable / float(MIN_CONSECUTIVE_UNBOOKABLE_FOR_STRONG_OPEN))
    fresh_s = 1.0
    opp = (
        0.30 * scarcity_s
        + 0.20 * venue_s
        + 0.20 * timing_s
        + 0.15 * ttl_s
        + 0.15 * conf_s
    )
    if event_type == "WEAK_OPEN":
        opp *= 0.92
    return {
        "opportunity_score": round(opp, 4),
        "scarcity_score": round(scarcity_s, 4),
        "venue_score": round(venue_s, 4),
        "timing_score": round(timing_s, 4),
        "ttl_score": ttl_s,
        "confidence_score": round(conf_s, 4),
        "freshness_score": fresh_s,
    }


def process_opportunity_poll(
    db: Session,
    *,
    bucket_id: str,
    merged_hits: list[dict[str, Any]] | None,
    raw_error_count: int,
    provider: str,
    time_slot: str,
    now: datetime | None = None,
) -> dict[str, Any]:
    """
    After a Resy inclusive fetch: persist poll run, update venue_bucket_states, insert opportunity_events.
    merged_hits None → skip (non-Resy provider).
    """
    if merged_hits is None or provider != "resy":
        return {"skipped": True, "reason": "not_resy_or_no_hits"}

    now = now or datetime.now(timezone.utc)
    n_venues = len(merged_hits)
    if n_venues == 0:
        return {"skipped": True, "reason": "no_hits"}

    coverage = compute_coverage_score(n_venues, raw_error_count)
    poll_run = OpportunityPollRun(
        id=uuid.uuid4(),
        bucket_id=bucket_id,
        polled_at=now,
        success=True,
        coverage_score=coverage,
        venue_hit_count=n_venues,
        error_count=raw_error_count,
        provider=provider,
    )
    db.add(poll_run)
    db.flush()

    venue_map: dict[str, dict[str, Any]] = {}
    for h in merged_hits:
        if not isinstance(h, dict):
            continue
        vid = venue_id_from_hit(h)
        if not vid:
            continue
        venue_map[vid] = h

    known_ids = {
        r.venue_id
        for r in db.query(VenueBucketState).filter(VenueBucketState.bucket_id == bucket_id).all()
    }
    all_ids = set(venue_map.keys()) | known_ids

    stats = {"updated": 0, "strong_open": 0, "weak_open": 0, "coverage": coverage}

    for vid in all_ids:
        hit = venue_map.get(vid)
        if coverage < MIN_COVERAGE_SCORE:
            curr = UNKNOWN
        else:
            curr = extract_state_from_hit(hit)

        row = (
            db.query(VenueBucketState)
            .filter(VenueBucketState.bucket_id == bucket_id, VenueBucketState.venue_id == vid)
            .first()
        )
        prev_state = row.current_state if row else None
        prior_unbook_streak = int(row.consecutive_unbookable_polls or 0) if row else 0
        prior_abs_streak = int(row.consecutive_absent_polls or 0) if row else 0

        if row is None:
            row = VenueBucketState(
                bucket_id=bucket_id,
                venue_id=vid,
                current_state=curr,
                previous_state=None,
                consecutive_bookable_polls=0,
                consecutive_unbookable_polls=0,
                consecutive_absent_polls=0,
                first_seen_at=now,
            )
            db.add(row)

        # Transition detection (before mutating streak counters for *this* poll's end state)
        event_type: str | None = None
        reason_codes: list[str] = []

        if coverage >= MIN_COVERAGE_SCORE:
            if prev_state == UNBOOKABLE and curr == BOOKABLE and prior_unbook_streak >= MIN_CONSECUTIVE_UNBOOKABLE_FOR_STRONG_OPEN:
                event_type = "STRONG_OPEN"
                reason_codes.append("unbookable_to_bookable")
                reason_codes.append(f"unbook_streak>={MIN_CONSECUTIVE_UNBOOKABLE_FOR_STRONG_OPEN}")
            elif prev_state == ABSENT and curr == BOOKABLE and prior_abs_streak >= 1:
                event_type = "WEAK_OPEN"
                reason_codes.append("absent_to_bookable")

        # Cooldown: skip duplicate events
        if event_type:
            cutoff = now - timedelta(minutes=OPPORTUNITY_COOLDOWN_MINUTES)
            recent = (
                db.query(OpportunityEvent.id)
                .filter(
                    OpportunityEvent.bucket_id == bucket_id,
                    OpportunityEvent.venue_id == vid,
                    OpportunityEvent.detected_at >= cutoff,
                )
                .first()
            )
            if recent:
                event_type = None
                reason_codes = []

        if event_type:
            streak_for_score = prior_unbook_streak if event_type == "STRONG_OPEN" else prior_abs_streak
            scores = compute_opportunity_scores_v1(
                event_type,
                hit,
                coverage,
                streak_for_score,
                time_slot,
            )
            if event_type == "WEAK_OPEN" and (
                scores["opportunity_score"] < WEAK_OPEN_MIN_OPPORTUNITY_SCORE
                or scores["venue_score"] < WEAK_OPEN_MIN_VENUE_SCORE
            ):
                event_type = None
            else:
                vname = venue_name_from_hit(hit) if hit else (row.venue_name_snapshot or "")
                ev = OpportunityEvent(
                    id=uuid.uuid4(),
                    bucket_id=bucket_id,
                    venue_id=vid,
                    poll_run_id=poll_run.id,
                    event_type=event_type,
                    detected_at=now,
                    opportunity_score=scores["opportunity_score"],
                    scarcity_score=scores["scarcity_score"],
                    venue_score=scores["venue_score"],
                    timing_score=scores["timing_score"],
                    ttl_score=scores["ttl_score"],
                    confidence_score=scores["confidence_score"],
                    freshness_score=scores["freshness_score"],
                    reason_codes_json=json.dumps(reason_codes),
                    notified=False,
                    venue_name=vname or None,
                )
                db.add(ev)
                if event_type == "STRONG_OPEN":
                    stats["strong_open"] += 1
                else:
                    stats["weak_open"] += 1
                logger.info(
                    "Opportunity %s bucket=%s venue=%s score=%s coverage=%.2f",
                    event_type,
                    bucket_id,
                    vid,
                    scores["opportunity_score"],
                    coverage,
                )

        # Update rolling counters and state
        row.previous_state = prev_state
        row.current_state = curr
        row.last_seen_at = now
        if hit:
            nm = venue_name_from_hit(hit)
            if nm:
                row.venue_name_snapshot = nm[:512]

        if curr == BOOKABLE:
            row.consecutive_bookable_polls = (row.consecutive_bookable_polls or 0) + 1
            row.consecutive_unbookable_polls = 0
            row.consecutive_absent_polls = 0
            row.last_bookable_at = now
        elif curr == UNBOOKABLE:
            row.consecutive_unbookable_polls = (row.consecutive_unbookable_polls or 0) + 1 if prev_state == UNBOOKABLE else 1
            row.consecutive_bookable_polls = 0
            row.consecutive_absent_polls = 0
            row.last_unbookable_at = now
        elif curr == ABSENT:
            row.consecutive_absent_polls = (row.consecutive_absent_polls or 0) + 1 if prev_state == ABSENT else 1
            row.consecutive_bookable_polls = 0
            row.consecutive_unbookable_polls = 0
        else:  # UNKNOWN
            row.consecutive_bookable_polls = 0
            row.consecutive_unbookable_polls = 0
            row.consecutive_absent_polls = 0

        stats["updated"] += 1

    return stats

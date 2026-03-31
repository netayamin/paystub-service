"""
Snag drop eligibility — predicates over stored drop_events facts.

TRUE DROP DEFINITION (v2):
  A slot is a true drop if and only if it was NOT present in the baseline scan
  (the first successful poll for that bucket). This means the venue was fully
  booked (or that slot didn't exist) when we started watching. Any later
  appearance is a genuine reopening.

  This is enforced at write time in buckets.py:
      drops = (curr_set - prev_set) - baseline_set

  Therefore every DropEvent row in the DB is already a confirmed true drop.
  This module's only job is to filter out legacy/backfill rows that pre-date
  the baseline-subtraction logic (evidence = "unknown").

Evidence labels (what they mean under v2):
- nonempty_prev_delta : strongest — both prev comparison and baseline confirm the drop
- empty_prev_delta    : prev was empty on this poll (unusual); baseline still guarantees the drop
- baseline_only       : edge case — baseline had slots but prev was empty; slot proven not-in-baseline
- first_poll_bucket   : baseline was empty (venue fully booked at scan start); slot is a true drop
- unknown             : legacy backfill; no guarantee — disqualified from home feed
"""
from __future__ import annotations

_EVIDENCE_RANK = {
    "nonempty_prev_delta": 4,
    "empty_prev_delta": 3,
    "baseline_only": 2,
    "first_poll_bucket": 1,
    "unknown": 0,
}


def stronger_eligibility_evidence(a: str | None, b: str | None) -> str:
    """Prefer stronger (more informative) evidence when merging slots onto one card."""
    aa = (a or "unknown").strip() or "unknown"
    bb = (b or "unknown").strip() or "unknown"
    return aa if _EVIDENCE_RANK.get(aa, 0) >= _EVIDENCE_RANK.get(bb, 0) else bb


def qualified_for_home_feed(
    eligibility_evidence: str | None,
    bucket_successful_poll_count: int | None,  # kept for API compat, no longer used
) -> bool:
    """True if a drop event may appear on ranked/ticker boards.

    Under v2 (baseline-subtraction), all non-unknown evidence is qualified:
    the slot was guaranteed to not be present in the baseline scan.
    Only 'unknown' (legacy backfill) rows are rejected.
    """
    ev = (eligibility_evidence or "unknown").strip() or "unknown"
    return ev != "unknown"


def rank_strength_multiplier(eligibility_evidence: str | None) -> float:
    """Multiply feed priority / ticker scores (interpretable tiering, Task 3.2)."""
    ev = (eligibility_evidence or "unknown").strip() or "unknown"
    if ev == "nonempty_prev_delta":
        return 1.0
    if ev == "empty_prev_delta":
        return 0.88
    if ev == "baseline_only":
        return 0.72
    return 0.55


def push_notification_allowed(eligibility_evidence: str | None) -> bool:
    """Stricter than home feed: only diff-backed signals (Task 4.2)."""
    ev = (eligibility_evidence or "unknown").strip() or "unknown"
    return ev in ("nonempty_prev_delta", "empty_prev_delta")

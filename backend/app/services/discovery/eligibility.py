"""
Snag drop eligibility (Task 3.1) — predicates over **stored** `drop_events` facts.

Ground truth: we do not have Resy "fully booked"; "new" is diff-based. This module
decides **whether** a persisted row (or its summary fields on a feed card) is
strong enough to treat as a **home-feed / push–worthy** "Snag drop", separate
from Task 3.1b **ordering**.

Disqualifiers (conservative Phase A):
- **unknown** — legacy / backfill / missing writer; do not market as diff-proven.
- **first_poll_bucket** — no stable prev chain; thin history.
- **baseline_only** when the bucket has **not** completed enough successful polls
  (`successful_poll_count` < MIN_POLLS_FOR_BASELINE_TRUST).

**empty_prev_delta** stays on the feed (ambiguous but observable empty prior).
**nonempty_prev_delta** is the strongest diff signal.

See also: `docs/RANKING_SPEC.md` (Task 3.1b) and `TARGET_SCHEMA_AND_INVARIANTS.md` §4.
"""
from __future__ import annotations

# Bucket must have this many completed polls before baseline_only rows qualify.
MIN_POLLS_FOR_BASELINE_TRUST = 3

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
    bucket_successful_poll_count: int | None,
) -> bool:
    """True if a just-opened contribution may appear on ranked/ticker boards."""
    ev = (eligibility_evidence or "unknown").strip() or "unknown"
    polls = int(bucket_successful_poll_count or 0)
    if ev in ("unknown", "first_poll_bucket"):
        return False
    if ev == "baseline_only" and polls < MIN_POLLS_FOR_BASELINE_TRUST:
        return False
    return True


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

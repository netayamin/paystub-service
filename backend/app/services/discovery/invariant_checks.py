"""Postgres invariant checks for discovery tables (Task 1.5). Used by scripts and tests."""
from __future__ import annotations

from sqlalchemy import text

from app.db.session import SessionLocal

_ALLOWED_EVIDENCE = frozenset(
    {
        "unknown",
        "nonempty_prev_delta",
        "empty_prev_delta",
        "baseline_only",
        "first_poll_bucket",
    }
)


def run_discovery_invariant_checks() -> list[str]:
    """Return human-readable error strings; empty list means all checks passed."""
    errors: list[str] = []
    db = SessionLocal()
    try:
        n = db.execute(
            text("SELECT COUNT(*) FROM drop_events WHERE user_facing_opened_at IS NULL")
        ).scalar()
        if n is not None and int(n) > 0:
            errors.append(f"drop_events.user_facing_opened_at IS NULL: {n} rows")

        rows = db.execute(
            text("SELECT DISTINCT eligibility_evidence FROM drop_events")
        ).fetchall()
        bad_vals = sorted(
            {str(r[0]) for r in rows if r[0] is not None and str(r[0]) not in _ALLOWED_EVIDENCE}
        )
        if bad_vals:
            errors.append(f"drop_events.eligibility_evidence not in allowed set: {bad_vals}")
    finally:
        db.close()
    return errors

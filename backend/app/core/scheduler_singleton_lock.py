"""
Session-level Postgres advisory locks so only one backend instance runs singleton jobs.

Bucket polls already use pg_try_advisory_xact_lock per bucket_id in run_poll_for_bucket.
Daily sliding-window prune and push use these fixed (k1, k2) pairs so duplicate schedulers
on multiple hosts do not double-run heavy work or duplicate notifications.

Always release in finally — session-level locks survive commit and must not leak across
pooled connections (unlock before Session.close).
"""
from __future__ import annotations

import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# Fixed int32 pairs — must not collide with each other or with application use of advisory locks.
_K1 = 582_947_001
_SLIDING_K2 = 1
_PUSH_K2 = 2


def try_acquire_sliding_window_leader(db: Session) -> bool:
    try:
        ok = bool(db.execute(text("SELECT pg_try_advisory_lock(:k1, :k2)"), {"k1": _K1, "k2": _SLIDING_K2}).scalar())
    except Exception as e:
        # SQLite / non-Postgres test DB: no advisory locks — behave as single leader.
        logger.debug("Sliding-window advisory lock unavailable (%s); running job anyway", e)
        return True
    if not ok:
        logger.info("Sliding-window job: advisory lock not acquired — another instance is running it (skip)")
    return ok


def release_sliding_window_leader(db: Session) -> None:
    try:
        db.execute(text("SELECT pg_advisory_unlock(:k1, :k2)"), {"k1": _K1, "k2": _SLIDING_K2})
        db.commit()
    except Exception as e:
        logger.debug("Sliding-window leader unlock skipped: %s", e)
        db.rollback()


def try_acquire_push_leader(db: Session) -> bool:
    try:
        ok = bool(db.execute(text("SELECT pg_try_advisory_lock(:k1, :k2)"), {"k1": _K1, "k2": _PUSH_K2}).scalar())
    except Exception as e:
        logger.debug("Push advisory lock unavailable (%s); running job anyway", e)
        return True
    if not ok:
        logger.debug("Push job: advisory lock not acquired — another instance is sending (skip)")
    return ok


def release_push_leader(db: Session) -> None:
    try:
        db.execute(text("SELECT pg_advisory_unlock(:k1, :k2)"), {"k1": _K1, "k2": _PUSH_K2})
        db.commit()
    except Exception as e:
        logger.debug("Push leader unlock skipped: %s", e)
        db.rollback()

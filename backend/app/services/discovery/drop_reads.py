"""Read helpers for drop_events (Task 2.3) — facts for feed/ranking/push; no policy."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import tuple_
from sqlalchemy.orm import Session

from app.models.discovery_bucket import DiscoveryBucket
from app.models.drop_event import DropEvent


def latest_drop_row_per_pair(
    db: Session,
    pairs: list[tuple[str, str]],
    opened_not_before: datetime,
) -> dict[tuple[str, str], dict[str, Any]]:
    """
    For each (bucket_id, slot_id), return metadata from the latest DropEvent at or after opened_not_before.
    """
    if not pairs:
        return {}
    rows = (
        db.query(DropEvent)
        .filter(
            tuple_(DropEvent.bucket_id, DropEvent.slot_id).in_(pairs),
            DropEvent.user_facing_opened_at >= opened_not_before,
        )
        .all()
    )
    best: dict[tuple[str, str], DropEvent] = {}
    for row in rows:
        k = (row.bucket_id, row.slot_id)
        cur = best.get(k)
        if cur is None or row.user_facing_opened_at > cur.user_facing_opened_at:
            best[k] = row
    return {
        k: {
            "eligibility_evidence": r.eligibility_evidence,
            "user_facing_opened_at": r.user_facing_opened_at,
            "prior_prev_slot_count": r.prior_prev_slot_count,
            "prior_snapshot_included_slot": r.prior_snapshot_included_slot,
        }
        for k, r in best.items()
    }


def successful_poll_count_by_bucket(db: Session, bucket_ids: list[str]) -> dict[str, int]:
    """discovery_buckets.successful_poll_count for thin-history signals."""
    if not bucket_ids:
        return {}
    rows = (
        db.query(DiscoveryBucket.bucket_id, DiscoveryBucket.successful_poll_count)
        .filter(DiscoveryBucket.bucket_id.in_(bucket_ids))
        .all()
    )
    return {bid: int(n or 0) for bid, n in rows}

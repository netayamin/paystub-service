"""
Discovery blueprint: per-bucket state and drop formula.

- Bucket = (date_str, time_slot) with time_slot in {"15:00", "19:00"}. 28 buckets (14 days × 2).
- 15:00 and 19:00 are anchor times (3pm, 7pm); Resy returns availability ±3h around each.
  So "3pm" = ~12pm–6pm, "7pm" = ~4pm–10pm.
- slot_id = hash(provider, venue_id, actual_time) — one id per venue+reservation-time so baseline
  is "restaurants and their times" (actual_time = slot start e.g. "2026-02-18 20:30:00").
- Per bucket: baseline_slot_ids (T0), prev_slot_ids (last poll), curr_slot_ids (this poll).
  new_vs_baseline = C - B, added_vs_prev = C - P, removed_vs_prev = P - C,
  fresh (drops) = (C - P) ∩ (C - B).
- Drops = (curr - prev) ∩ (curr - baseline); emit to drop_events with dedupe_key.
"""
import hashlib
import json
import logging
import uuid
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone
from typing import Callable

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.discovery_config import (
    DISCOVERY_MAX_CONCURRENT_BUCKETS,
    DISCOVERY_PARTY_SIZES,
    DISCOVERY_TIME_SLOTS,
    DISCOVERY_WINDOW_DAYS,
)
from app.db.session import SessionLocal


def window_start_date() -> date:
    """First day of the 14-day discovery window. After 11 PM server local time, use tomorrow so we drop today (odds anything opens are very low)."""
    now = datetime.now()
    if now.hour >= 23:
        return date.today() + timedelta(days=1)
    return date.today()

from app.models.availability_session import AvailabilitySession
from app.models.discovery_bucket import DiscoveryBucket
from app.models.drop_event import DropEvent
from app.models.slot_availability import SlotAvailability
from app.models.venue import Venue
from app.services.aggregation import aggregate_closed_events_into_metrics
from app.services.providers import get_provider

logger = logging.getLogger(__name__)

# In-memory only: closed-event data for aggregation (we never persist CLOSED rows to drop_events)
# session_id: when set, aggregate marks session as aggregated (idempotency).
ClosedEventData = namedtuple(
    "ClosedEventData",
    ["venue_id", "venue_name", "drop_duration_seconds", "slot_date", "bucket_id", "session_id"],
    defaults=(None,),
)

# From discovery_config (env-driven); aliased for in-file use.
WINDOW_DAYS = DISCOVERY_WINDOW_DAYS
TIME_SLOTS = DISCOVERY_TIME_SLOTS
PARTY_SIZES = DISCOVERY_PARTY_SIZES

TIME_WINDOW_HOURS = 2  # ±2h: 15:00 → ~1pm–5pm, 19:00 → ~5pm–9pm
FETCH_TIMEOUT_SECONDS = 15
MAX_PAGES = 2
PER_PAGE = 200
# Buckets not scanned within this many hours are excluded from just-opened and still-open (avoid passing stale data)
STALE_BUCKET_HOURS = 4
# Cap drop_events loaded for still-open view to avoid unbounded memory and DB load (scalability)
STILL_OPEN_EVENTS_LIMIT = 10_000


def _is_bucket_fresh(scanned_at: datetime | None) -> bool:
    """True if bucket was scanned within STALE_BUCKET_HOURS (so we can safely use its prev_slot_ids)."""
    if not scanned_at:
        return False
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_BUCKET_HOURS)
    if scanned_at.tzinfo is None:
        scanned_at = scanned_at.replace(tzinfo=timezone.utc)
    return scanned_at >= cutoff


def bucket_id(date_str: str, time_slot: str) -> str:
    """Stable bucket key. E.g. 2026-02-12_15:00."""
    return f"{date_str}_{time_slot}"


def slot_id(venue_id: str, actual_time: str, provider: str = "resy") -> str:
    """
    Stable slot key for fast diff: one id per provider + venue + actual time.
    Delegates to providers.types.slot_id for consistency with provider output.
    """
    from app.services.providers.types import slot_id as make_slot_id
    return make_slot_id(provider, venue_id or "", actual_time or "")


def all_bucket_ids(today: date) -> list[tuple[str, str, str]]:
    """Returns (bucket_id, date_str, time_slot) for the 14-day × 2 slots window."""
    out = []
    for offset in range(WINDOW_DAYS):
        day = today + timedelta(days=offset)
        date_str = day.isoformat()
        for ts in TIME_SLOTS:
            out.append((bucket_id(date_str, ts), date_str, ts))
    return out


def fetch_for_bucket(
    date_str: str,
    time_slot: str,
    party_sizes: list[int],
    provider: str = "resy",
) -> list[dict]:
    """
    Fetch current availability for one bucket via the given provider.
    Returns one row per (venue, actual_time): { "slot_id", "venue_id", "venue_name", "payload" }.
    All providers (Resy, OpenTable, etc.) return the same normalized shape.
    """
    try:
        prov = get_provider(provider)
    except KeyError:
        logger.warning("Unknown provider %s, skipping bucket %s", provider, bucket_id(date_str, time_slot))
        return []
    try:
        results = prov.search_availability(date_str, time_slot, party_sizes)
    except Exception as e:
        logger.warning("Provider %s search failed bucket=%s: %s", provider, bucket_id(date_str, time_slot), e)
        return []
    return [r.to_row() for r in results]


def _parse_slot_ids_json(js: str | None) -> set[str]:
    if not js:
        return set()
    try:
        arr = json.loads(js)
        return set(str(x) for x in arr if x)
    except (TypeError, json.JSONDecodeError):
        return set()


def _time_bucket_from_slot(time_slot: str) -> str:
    """Map bucket time_slot to time_bucket: 19:00 = prime, 15:00 = off_peak."""
    return "prime" if time_slot == "19:00" else "off_peak"


def _slot_date_time_from_payload(payload: dict | None, date_str: str) -> tuple[str | None, str | None]:
    """Extract slot_date and slot_time from payload (availability_times[0] or similar). Returns (slot_date, slot_time)."""
    if not payload or not isinstance(payload, dict):
        return date_str, None
    times = payload.get("availability_times") or []
    if not times or not isinstance(times, list):
        return date_str, None
    first = times[0]
    if not first or not isinstance(first, str):
        return date_str, None
    first = first.strip()
    # "2026-02-18 20:30:00" or "2026-02-18T20:30:00"
    if "T" in first:
        parts = first.split("T")
        return (parts[0] if len(parts) > 0 else date_str), (parts[1][:8] if len(parts) > 1 else None)
    if " " in first:
        parts = first.split(" ", 1)
        return (parts[0] if len(parts) > 0 else date_str), (parts[1][:8] if len(parts) > 1 else None)
    return date_str, first[:8] if len(first) >= 5 else None


def _upsert_venue(db: Session, venue_id: str | None, venue_name: str | None) -> None:
    """Upsert venue for normalization; called when emitting DropEvent."""
    if not venue_id or not str(venue_id).strip():
        return
    vid = str(venue_id).strip()
    name = (venue_name or "").strip() or None
    row = db.query(Venue).filter(Venue.venue_id == vid).first()
    now = datetime.now(timezone.utc)
    if row:
        if name:
            row.venue_name = name
        row.last_seen_at = now
    else:
        db.add(Venue(venue_id=vid, venue_name=name))


def run_baseline_for_bucket(
    db: Session, bid: str, date_str: str, time_slot: str, provider: str = "resy"
) -> int:
    """
    Fetch current state for bucket and set baseline = prev = curr. Replaces any previous baseline.
    Does NOT write to slot_availability or availability_sessions (no sessions/metrics from baseline).
    Returns slot count.
    """
    rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=provider)
    slot_ids = [r["slot_id"] for r in rows]
    now = datetime.now(timezone.utc)
    row = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id == bid).first()
    js = json.dumps(sorted(slot_ids))
    if row:
        # Overwrite previous baseline and prev with new snapshot (previous one is replaced, not kept)
        row.baseline_slot_ids_json = js
        row.prev_slot_ids_json = js
        row.scanned_at = now
    else:
        db.add(DiscoveryBucket(bucket_id=bid, date_str=date_str, time_slot=time_slot, baseline_slot_ids_json=js, prev_slot_ids_json=js, scanned_at=now))
    db.commit()
    logger.info("Baseline bucket %s: %s slots", bid, len(slot_ids))
    return len(slot_ids)


def refresh_baselines_for_all_buckets(
    db: Session,
    today: date | None = None,
    *,
    progress_callback: Callable[[str, int, int, int], None] | None = None,
) -> dict:
    """
    Re-run baseline for all 28 buckets in place (current search area). For each bucket,
    overwrites baseline_slot_ids_json and prev_slot_ids_json with a fresh fetch — the
    previous baseline is replaced (not kept). Does not delete discovery_buckets or
    drop_events rows. Use after changing the Resy search bounding box so "just opened" /
    "still open" are correct for the new area without wiping drop history.
    progress_callback: optional (bucket_id, index_1based, total, slot_count) after each bucket.
    Returns { "buckets_refreshed", "buckets_total", "errors" }.
    """
    if today is None:
        today = window_start_date()
    ensure_buckets(db, today)
    buckets = all_bucket_ids(today)
    total = len(buckets)
    errors = []
    for i, (bid, date_str, time_slot) in enumerate(buckets, start=1):
        try:
            slot_count = run_baseline_for_bucket(db, bid, date_str, time_slot)
            if progress_callback:
                progress_callback(bid, i, total, slot_count)
        except Exception as e:
            logger.exception("Refresh baseline bucket %s failed: %s", bid, e)
            errors.append(bid)
    return {
        "buckets_refreshed": total - len(errors),
        "buckets_total": total,
        "errors": errors,
    }


def _advisory_lock_key(bucket_id: str) -> int:
    """Deterministic bigint for PostgreSQL advisory lock (one bucket = one in-flight poll)."""
    h = hashlib.sha256(bucket_id.encode()).digest()[:8]
    return int.from_bytes(h, "big") % (2**63)


def run_poll_for_bucket(
    db: Session, bid: str, date_str: str, time_slot: str, provider: str = "resy"
) -> tuple[int, int, dict]:
    """
    Poll one bucket: fetch curr (network, outside tx), then in a short write tx: lease bucket,
    compute diff, apply projection + sessions, commit. Apply only if our run is newer (last-writer-wins).
    Returns (drops_emitted, current_slot_count, invariant_stats).
    """
    # Network I/O first (no DB transaction)
    rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=provider)
    curr_set = {r["slot_id"] for r in rows}

    bucket_row = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id == bid).first()
    # Per-bucket lease: only one writer at a time (critical for 30s + thread pool / multi-instance)
    lock_key = _advisory_lock_key(bid)
    acquired = db.execute(text("SELECT pg_try_advisory_xact_lock(:k)"), {"k": lock_key}).scalar()
    if not acquired:
        logger.warning("Bucket %s: could not acquire advisory lock, skipping (another worker has it)", bid)
        db.rollback()
        return 0, len(curr_set), {"skipped": True, "reason": "lock"}

    now = datetime.now(timezone.utc)
    B = P = C = 0
    baseline_set: set[str] = set()
    prev_set: set[str] = set()

    if not bucket_row:
        js = json.dumps(sorted(curr_set))
        db.add(DiscoveryBucket(bucket_id=bid, date_str=date_str, time_slot=time_slot, baseline_slot_ids_json=js, prev_slot_ids_json=js, scanned_at=now))
        db.commit()
        return 0, len(curr_set), {"B": len(curr_set), "P": len(curr_set), "C": len(curr_set), "baseline_ready": True, "emitted": 0, "baseline_echo": 0, "prev_echo": 0}

    baseline_js = bucket_row.baseline_slot_ids_json
    if baseline_js is None:
        js = json.dumps(sorted(curr_set))
        bucket_row.baseline_slot_ids_json = js
        bucket_row.prev_slot_ids_json = js
        bucket_row.scanned_at = now
        db.commit()
        logger.info("Bucket %s: initialized baseline (was None), %s slots", bid, len(curr_set))
        return 0, len(curr_set), {"B": len(curr_set), "P": len(curr_set), "C": len(curr_set), "baseline_ready": True, "emitted": 0, "baseline_echo": 0, "prev_echo": 0}

    baseline_set = _parse_slot_ids_json(baseline_js)
    prev_set = _parse_slot_ids_json(bucket_row.prev_slot_ids_json)
    B, P, C = len(baseline_set), len(prev_set), len(curr_set)

    opened_vs_prev = curr_set - prev_set
    opened_vs_baseline = curr_set - baseline_set
    drops = opened_vs_prev & opened_vs_baseline

    emitted_set = set(drops)
    baseline_echo = len(emitted_set & baseline_set)
    prev_echo = len(emitted_set & prev_set)
    if baseline_echo > 0:
        logger.error("INVARIANT VIOLATION bucket=%s: baseline_echo=%s (emitted ∩ baseline must be 0)", bid, baseline_echo)
    if prev_echo > 0:
        logger.error("INVARIANT VIOLATION bucket=%s: prev_echo=%s (emitted ∩ prev must be 0)", bid, prev_echo)

    run_id = str(uuid.uuid4())
    time_bucket_val = _time_bucket_from_slot(time_slot)
    closed_slots = prev_set - curr_set
    by_slot = {r["slot_id"]: r for r in rows}

    # --- Projection + sessions (scalable: soft state, no deletes) ---
    emitted = 0
    for sid in drops:
        r = by_slot.get(sid)
        payload = r.get("payload") if r else None
        slot_date_val, slot_time_val = _slot_date_time_from_payload(payload, date_str)
        neighborhood_val = price_range_val = None
        if isinstance(payload, dict):
            loc = payload.get("location")
            nh = payload.get("neighborhood") or (loc.get("neighborhood") if isinstance(loc, dict) else None)
            if nh is not None:
                neighborhood_val = str(nh)[:128] or None
            pr = payload.get("price_range")
            if pr is not None:
                price_range_val = str(pr)[:32] or None
        stmt = pg_insert(SlotAvailability).values(
            bucket_id=bid,
            slot_id=sid,
            state="open",
            opened_at=now,
            last_seen_at=now,
            venue_id=r.get("venue_id") if r else None,
            venue_name=r.get("venue_name") if r else None,
            payload_json=json.dumps(r["payload"]) if r else None,
            run_id=run_id,
            updated_at=now,
            time_bucket=time_bucket_val,
            slot_date=slot_date_val,
            slot_time=slot_time_val,
            provider=provider,
            neighborhood=neighborhood_val,
            price_range=price_range_val,
        ).on_conflict_do_update(
            index_elements=["bucket_id", "slot_id"],
            set_={
                "state": "open",
                "opened_at": now,
                "last_seen_at": now,
                "venue_id": r.get("venue_id") if r else None,
                "venue_name": r.get("venue_name") if r else None,
                "payload_json": json.dumps(r["payload"]) if r else None,
                "run_id": run_id,
                "updated_at": now,
                "time_bucket": time_bucket_val,
                "slot_date": slot_date_val,
                "slot_time": slot_time_val,
                "provider": provider,
                "neighborhood": neighborhood_val,
                "price_range": price_range_val,
                "closed_at": None,
            },
            where=text("slot_availability.updated_at < excluded.updated_at"),
        )
        db.execute(stmt)
        emitted += 1
        # Also write to drop_events so aggregation (venue_metrics, market_metrics) and any drop_events readers get data
        dedupe_key = f"{bid}|{sid}|{now.strftime('%Y-%m-%dT%H:%M')}"
        try:
            db.execute(
                pg_insert(DropEvent)
                .values(
                    bucket_id=bid,
                    slot_id=sid,
                    opened_at=now,
                    venue_id=r.get("venue_id") if r else None,
                    venue_name=r.get("venue_name") if r else None,
                    payload_json=json.dumps(r["payload"]) if r else None,
                    dedupe_key=dedupe_key,
                    time_bucket=time_bucket_val,
                    slot_date=slot_date_val,
                    slot_time=slot_time_val,
                    provider=provider,
                    neighborhood=neighborhood_val,
                    price_range=price_range_val,
                )
                .on_conflict_do_nothing(index_elements=["dedupe_key"])
            )
        except Exception as e:
            logger.debug("DropEvent insert skip (duplicate or error): %s", e)
        # At most one open session per (bucket_id, slot_id): only insert if none exists (idempotent)
        existing_open = (
            db.query(AvailabilitySession)
            .filter(
                AvailabilitySession.bucket_id == bid,
                AvailabilitySession.slot_id == sid,
                AvailabilitySession.closed_at.is_(None),
            )
            .first()
        )
        if not existing_open:
            db.add(AvailabilitySession(
                bucket_id=bid,
                slot_id=sid,
                opened_at=now,
                venue_id=r.get("venue_id") if r else None,
                venue_name=r.get("venue_name") if r else None,
                slot_date=slot_date_val,
                provider=provider,
            ))
    to_aggregate: list[ClosedEventData] = []
    for sid in closed_slots:
        row = db.query(SlotAvailability).filter(
            SlotAvailability.bucket_id == bid,
            SlotAvailability.slot_id == sid,
        ).first()
        if not row or not row.opened_at:
            continue
        opened_at_dt = row.opened_at.replace(tzinfo=timezone.utc) if row.opened_at.tzinfo is None else row.opened_at
        duration_seconds = int((now - opened_at_dt).total_seconds())
        if duration_seconds < 0:
            continue
        db.execute(
            pg_insert(SlotAvailability).values(
                bucket_id=bid,
                slot_id=sid,
                state="closed",
                opened_at=row.opened_at,
                closed_at=now,
                last_seen_at=now,
                venue_id=row.venue_id,
                venue_name=row.venue_name,
                payload_json=row.payload_json,
                run_id=run_id,
                updated_at=now,
                time_bucket=row.time_bucket or time_bucket_val,
                slot_date=row.slot_date or date_str,
                slot_time=row.slot_time,
                provider=row.provider or provider,
                neighborhood=row.neighborhood,
                price_range=row.price_range,
            ).on_conflict_do_update(
                index_elements=["bucket_id", "slot_id"],
                set_={
                    "state": "closed",
                    "closed_at": now,
                    "last_seen_at": now,
                    "run_id": run_id,
                    "updated_at": now,
                },
                where=text("slot_availability.updated_at < excluded.updated_at"),
            )
        )
        open_session = (
            db.query(AvailabilitySession)
            .filter(
                AvailabilitySession.bucket_id == bid,
                AvailabilitySession.slot_id == sid,
                AvailabilitySession.closed_at.is_(None),
            )
            .order_by(AvailabilitySession.opened_at.desc())
            .first()
        )
        if open_session:
            open_session.closed_at = now
            open_session.duration_seconds = duration_seconds
            to_aggregate.append(ClosedEventData(
                venue_id=row.venue_id,
                venue_name=row.venue_name,
                drop_duration_seconds=duration_seconds,
                slot_date=row.slot_date or date_str,
                bucket_id=bid,
                session_id=open_session.id,
            ))

    # Reconcile projection: mark as closed any slot not in curr_set (soft state)
    if curr_set is not None:
        q = db.query(SlotAvailability).filter(
            SlotAvailability.bucket_id == bid,
            SlotAvailability.state == "open",
            SlotAvailability.slot_id.notin_(list(curr_set)),
        )
        for row in q.all():
            row.state = "closed"
            row.closed_at = row.closed_at or now
            row.run_id = run_id
            row.updated_at = now
            open_sess = (
                db.query(AvailabilitySession)
                .filter(
                    AvailabilitySession.bucket_id == bid,
                    AvailabilitySession.slot_id == row.slot_id,
                    AvailabilitySession.closed_at.is_(None),
                )
                .first()
            )
            if open_sess and open_sess.opened_at:
                open_sess.closed_at = now
                open_sess.duration_seconds = int((now - (open_sess.opened_at.replace(tzinfo=timezone.utc) if open_sess.opened_at.tzinfo is None else open_sess.opened_at)).total_seconds())
                to_aggregate.append(ClosedEventData(
                    venue_id=row.venue_id,
                    venue_name=row.venue_name,
                    drop_duration_seconds=open_sess.duration_seconds,
                    slot_date=row.slot_date or date_str,
                    bucket_id=bid,
                    session_id=open_sess.id,
                ))

    bucket_row.prev_slot_ids_json = json.dumps(sorted(curr_set))
    bucket_row.scanned_at = now

    stats = {
        "B": B,
        "P": P,
        "C": C,
        "opened_vs_prev": len(opened_vs_prev),
        "opened_vs_baseline": len(opened_vs_baseline),
        "drops_computed": len(drops),
        "baseline_ready": True,
        "emitted": emitted,
        "closed_emitted": len(to_aggregate),
        "baseline_echo": baseline_echo,
        "prev_echo": prev_echo,
    }
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        logger.warning("Poll bucket %s commit failed: %s", bid, e)
        return emitted, len(curr_set), stats

    if to_aggregate:
        try:
            aggregate_closed_events_into_metrics(db, to_aggregate)
        except Exception as e:
            logger.warning("Aggregate closed events failed bucket=%s: %s", bid, e)

    logger.info(
        "bucket=%s B=%s P=%s C=%s | opened_vs_prev=%s opened_vs_baseline=%s | drops=%s emitted=%s closed=%s baseline_echo=%s prev_echo=%s",
        bid, B, P, C, len(opened_vs_prev), len(opened_vs_baseline), len(drops), emitted, len(to_aggregate), baseline_echo, prev_echo,
    )
    return emitted, len(curr_set), stats


def ensure_buckets(db: Session, today: date) -> None:
    """Ensure all 28 buckets exist (create with empty baseline/prev if missing)."""
    buckets = list(all_bucket_ids(today))
    existing_rows = (
        db.query(DiscoveryBucket.bucket_id)
        .filter(DiscoveryBucket.bucket_id.in_([b[0] for b in buckets]))
        .all()
    )
    existing_ids = {r[0] for r in existing_rows}
    to_add = [
        DiscoveryBucket(bucket_id=bid, date_str=date_str, time_slot=time_slot)
        for bid, date_str, time_slot in buckets
        if bid not in existing_ids
    ]
    if to_add:
        db.add_all(to_add)
        db.commit()


def prune_old_buckets(db: Session, today: date) -> int:
    """Remove buckets for dates before today. Returns count deleted."""
    today_str = today.isoformat()
    n = db.query(DiscoveryBucket).filter(DiscoveryBucket.date_str < today_str).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s discovery buckets (date < %s)", n, today_str)
    return n


def delete_closed_drop_events(db: Session, batch_size: int = 50_000) -> int:
    """
    No-op: we no longer persist CLOSED rows to drop_events. Kept for API compatibility (daily job).
    """
    return 0


def prune_old_drop_events(db: Session, today: date) -> int:
    """Legacy: prune drop_events by bucket_id. Kept for compatibility; primary projection is slot_availability."""
    today_str = today.isoformat()
    cutoff = f"{today_str}_15:00"
    n = db.query(DropEvent).filter(DropEvent.bucket_id < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s drop_events (date < %s)", n, today_str)
    return n


def prune_old_slot_availability(db: Session, today: date) -> int:
    """Remove projection rows for dates before today (retention). bucket_id format: YYYY-MM-DD_HH:MM."""
    today_str = today.isoformat()
    cutoff = f"{today_str}_15:00"
    n = db.query(SlotAvailability).filter(SlotAvailability.bucket_id < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s slot_availability (date < %s)", n, today_str)
    return n


def prune_old_sessions(db: Session, today: date) -> int:
    """Remove closed sessions for buckets before today (retention). Sessions table has bucket_id on each row... Actually AvailabilitySession doesn't have bucket_id in the migration - let me check. It does have bucket_id. So we can delete sessions where bucket_id < cutoff."""
    today_str = today.isoformat()
    cutoff = f"{today_str}_15:00"
    n = db.query(AvailabilitySession).filter(AvailabilitySession.bucket_id < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s availability_sessions (date < %s)", n, today_str)
    return n


def _poll_one_bucket(bid: str, date_str: str, time_slot: str) -> tuple[int, dict, str | None]:
    """
    Poll a single bucket in its own DB session (for use in thread pool).
    Returns (drops_emitted, stats, error_bid or None).
    """
    db = SessionLocal()
    try:
        n_drops, _, stats = run_poll_for_bucket(db, bid, date_str, time_slot)
        return (n_drops, stats, None)
    except Exception as e:
        logger.exception("Poll bucket %s failed: %s", bid, e)
        return (0, {}, bid)
    finally:
        db.close()


def run_poll_all_buckets(db: Session, today: date) -> dict:
    """
    Run poll for all 28 buckets in parallel so the whole run finishes in ~1–2 min.
    Each bucket is then re-scanned every 30s (next job run). Failed buckets are retried once (sequential).
    Returns { "buckets_polled", "drops_emitted", "last_scan_at", "errors", "invariants" }.
    """
    ensure_buckets(db, today)
    buckets = list(all_bucket_ids(today))
    drops_emitted = 0
    baseline_echo_total = 0
    prev_echo_total = 0
    buckets_baseline_ready = 0
    errors: list[tuple[str, str, str]] = []

    max_workers = min(len(buckets), DISCOVERY_MAX_CONCURRENT_BUCKETS)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_bucket = {
            executor.submit(_poll_one_bucket, bid, date_str, time_slot): (bid, date_str, time_slot)
            for bid, date_str, time_slot in buckets
        }
        for future in as_completed(future_to_bucket):
            bid, date_str, time_slot = future_to_bucket[future]
            try:
                n_drops, stats, err_bid = future.result()
                if err_bid:
                    errors.append((bid, date_str, time_slot))
                    continue
                drops_emitted += n_drops
                baseline_echo_total += stats.get("baseline_echo", 0)
                prev_echo_total += stats.get("prev_echo", 0)
                if stats.get("baseline_ready"):
                    buckets_baseline_ready += 1
            except Exception as e:
                logger.exception("Future for bucket %s raised: %s", bid, e)
                errors.append((bid, date_str, time_slot))

    # Retry failed buckets once (sequential, same process)
    retried: list[str] = []
    for bid, date_str, time_slot in list(errors):
        logger.warning("Retrying bucket %s", bid)
        n_drops, stats, err_bid = _poll_one_bucket(bid, date_str, time_slot)
        if err_bid:
            continue
        retried.append(bid)
        drops_emitted += n_drops
        baseline_echo_total += stats.get("baseline_echo", 0)
        prev_echo_total += stats.get("prev_echo", 0)
        if stats.get("baseline_ready"):
            buckets_baseline_ready += 1
    errors = [(b, d, t) for b, d, t in errors if b not in retried]
    error_ids = [b for b, _, _ in errors]

    if errors:
        logger.error(
            "run_poll_all_buckets: %s bucket(s) still failed after retry (major issue - these buckets will be stale): %s",
            len(errors),
            error_ids,
        )
    last_scan_at = None
    if buckets:
        # Latest scan time across any bucket (parallel run so any could be last)
        row = (
            db.query(DiscoveryBucket)
            .filter(DiscoveryBucket.bucket_id.in_([b[0] for b in buckets]))
            .order_by(DiscoveryBucket.scanned_at.desc())
            .limit(1)
            .first()
        )
        if row and row.scanned_at:
            last_scan_at = row.scanned_at.isoformat()
    if baseline_echo_total > 0:
        logger.error("INVARIANT run_poll_all: baseline_echo_total=%s (must be 0)", baseline_echo_total)
    if prev_echo_total > 0:
        logger.error("INVARIANT run_poll_all: prev_echo_total=%s (must be 0)", prev_echo_total)
    return {
        "buckets_polled": len(buckets) - len(errors),
        "drops_emitted": drops_emitted,
        "last_scan_at": last_scan_at,
        "errors": error_ids,
        "invariants": {
            "baseline_echo_total": baseline_echo_total,
            "prev_echo_total": prev_echo_total,
            "buckets_baseline_ready": buckets_baseline_ready,
            "buckets_total": len(buckets),
        },
    }


def get_feed(db: Session, since: datetime | None = None, limit: int = 100) -> list[dict]:
    """Return projection (slot_availability) for feed: currently open drops. If since set, only opened_at > since."""
    q = db.query(SlotAvailability).filter(SlotAvailability.state == "open").order_by(SlotAvailability.opened_at.desc())
    if since is not None:
        q = q.filter(SlotAvailability.opened_at > since)
    rows = q.limit(limit).all()
    return [
        {
            "id": f"{r.bucket_id}|{r.slot_id}",
            "bucket_id": r.bucket_id,
            "slot_id": r.slot_id,
            "opened_at": r.opened_at.isoformat() if r.opened_at else None,
            "venue_id": r.venue_id,
            "venue_name": r.venue_name,
            "payload": json.loads(r.payload_json) if r.payload_json else None,
        }
        for r in rows
    ]


def get_bucket_health(db: Session, today: date) -> list[dict]:
    """Return per-bucket last_scan_at and stale flag for health endpoint. Stale = not scanned within STALE_BUCKET_HOURS."""
    bucket_ids = [bid for bid, _d, _t in all_bucket_ids(today)]
    rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
    by_bucket = {r.bucket_id: r for r in rows}
    out = []
    for bid, date_str, time_slot in all_bucket_ids(today):
        row = by_bucket.get(bid)
        last_scan = row.scanned_at if row and row.scanned_at else None
        out.append({
            "bucket_id": bid,
            "date_str": date_str,
            "time_slot": time_slot,
            "last_scan_at": last_scan.isoformat() if last_scan else None,
            "baseline_count": len(_parse_slot_ids_json(row.baseline_slot_ids_json)) if row else 0,
            "stale": not _is_bucket_fresh(last_scan),
        })
    return out


def get_baseline_snapshot(db: Session, today: date | None = None) -> dict:
    """
    Return the initial snapshot (baseline) for all buckets: bucket_id, date_str, time_slot,
    baseline_count, baseline_slot_ids (list), and baseline_scanned_at (when baseline was set).
    Baseline stores slot_id hashes only; venue names are not stored for baseline slots.
    """
    if today is None:
        today = window_start_date()
    bucket_ids = [bid for bid, _d, _t in all_bucket_ids(today)]
    rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
    by_bucket = {r.bucket_id: r for r in rows}
    buckets = []
    for bid, date_str, time_slot in all_bucket_ids(today):
        row = by_bucket.get(bid)
        slot_ids = _parse_slot_ids_json(row.baseline_slot_ids_json) if row else set()
        buckets.append({
            "bucket_id": bid,
            "date_str": date_str,
            "time_slot": time_slot,
            "baseline_count": len(slot_ids),
            "baseline_slot_ids": sorted(slot_ids),
            "baseline_scanned_at": row.scanned_at.isoformat() if row and row.scanned_at else None,
        })
    return {
        "buckets": buckets,
        "hint": "Baseline = initial snapshot (slot_id hashes). Venue names are not stored for baseline; only for drops.",
    }


def _unique_venue_count(venues: list[dict]) -> int:
    """Count unique restaurants (by venue_id or name); same venue with multiple spots counts as 1."""
    seen = set()
    for v in venues or []:
        if not isinstance(v, dict):
            continue
        key = v.get("venue_id") or v.get("name") or ""
        if key:
            seen.add(str(key))
    return len(seen)


def get_calendar_counts(db: Session, today: date | None = None) -> dict:
    """
    Return result counts per date for the calendar bar graph.
    by_date[date_str] = number of unique restaurants (just_opened + still_open, deduped by venue per date).
    Same restaurant with multiple time slots counts once per date.
    """
    if today is None:
        today = window_start_date()
    date_strs = []
    seen_dates = set()
    for _bid, date_str, _ts in all_bucket_ids(today):
        if date_str not in seen_dates:
            seen_dates.add(date_str)
            date_strs.append(date_str)
    just_opened = get_just_opened_from_buckets(db, date_filter=None)
    still_open = get_still_open_from_buckets(db, today, date_filter=None)
    by_date_jo = {d["date_str"]: _unique_venue_count(d.get("venues")) for d in just_opened}
    by_date_so = {d["date_str"]: _unique_venue_count(d.get("venues")) for d in still_open}
    # Per date: unique venues from both; a venue in both lists still counts as 1
    by_date = {}
    for d in date_strs:
        venues_jo = next((x.get("venues") or [] for x in just_opened if x.get("date_str") == d), [])
        venues_so = next((x.get("venues") or [] for x in still_open if x.get("date_str") == d), [])
        combined = (venues_jo or []) + (venues_so or [])
        by_date[d] = _unique_venue_count(combined)
    return {"by_date": by_date, "dates": date_strs}


def get_notifications_by_date(
    db: Session,
    today: date | None = None,
    opened_within_minutes: int | None = None,
) -> dict:
    """
    New places (just opened) grouped by date for notifications.
    Returns by_date[date_str] = unique venue count, total, last_scan_at.
    Used by the frontend to show "X new places" per date and trigger alerts.
    """
    if today is None:
        today = window_start_date()
    from app.core.constants import JUST_OPENED_WITHIN_MINUTES

    minutes = opened_within_minutes if opened_within_minutes is not None else JUST_OPENED_WITHIN_MINUTES
    just_opened = get_just_opened_from_buckets(
        db,
        limit_events=5000,
        date_filter=None,
        opened_within_minutes=minutes,
    )
    by_date: dict[str, int] = {}
    total = 0
    for day in just_opened:
        date_str = day.get("date_str") or ""
        if not date_str:
            continue
        count = _unique_venue_count(day.get("venues"))
        if count > 0:
            by_date[date_str] = count
            total += count
    info = get_last_scan_info_buckets(db, today)
    return {
        "by_date": by_date,
        "total": total,
        "last_scan_at": info.get("last_scan_at"),
    }


def _bucket_time_slot(bucket_id: str) -> str:
    """Extract time_slot from bucket_id (e.g. 2026-02-12_15:00 -> 15:00)."""
    if "_" in bucket_id:
        return bucket_id.split("_")[1]
    return ""


def _venue_matches_party_sizes(payload: dict, party_sizes: list[int] | None) -> bool:
    """True if payload has at least one of the requested party sizes in party_sizes_available."""
    if not party_sizes:
        return True
    available = payload.get("party_sizes_available") or []
    if not available:
        return True
    return bool(set(available) & set(party_sizes))


def _time_str_to_minutes(t: str) -> int | None:
    """Parse time string to minutes since midnight. Handles ISO (T or space), HH:MM, HH:MM:SS, and 12h (e.g. 7:30 PM)."""
    if not t or not isinstance(t, str):
        return None
    t = t.strip().replace("Z", "")
    # ISO: 2026-02-14T21:15:00 or 2026-02-14 21:15:00
    if "T" in t:
        t = t.split("T")[1][:8]
    elif " " in t:
        # "2026-02-12 19:30:00" or "7:30 PM" -> take time part
        rest = t.split(" ")[-1]
        if rest.upper() in ("AM", "PM"):
            # "7:30 PM" -> need previous part
            parts = t.split()
            if len(parts) >= 2:
                t = parts[-2] + " " + parts[-1]
            else:
                t = rest
        else:
            t = rest[:8] if ":" in rest else t
    # 12-hour: "7:30 PM" or "7:30PM"
    if "M" in t.upper():
        try:
            time_part = t.upper().replace("AM", "").replace("PM", "").strip()
            time_parts = time_part.split(":")
            h = int(time_parts[0])
            m = int(time_parts[1]) if len(time_parts) > 1 else 0
            if "PM" in t.upper() and h != 12:
                h += 12
            elif "AM" in t.upper() and h == 12:
                h = 0
            if 0 <= h <= 23 and 0 <= m <= 59:
                return h * 60 + m
        except (ValueError, TypeError, IndexError):
            pass
        return None
    parts = t.split(":")
    if not parts:
        return None
    try:
        h = int(parts[0])
        m = int(parts[1]) if len(parts) > 1 else 0
        if 0 <= h <= 23 and 0 <= m <= 59:
            return h * 60 + m
    except (ValueError, TypeError):
        pass
    return None


def _venue_in_time_range(payload: dict, after_min: int | None, before_min: int | None) -> bool:
    """True if payload has at least one availability_times slot in [after_min, before_min] (inclusive). Minutes since midnight."""
    if after_min is None and before_min is None:
        return True
    times = payload.get("availability_times") or []
    if not times:
        return True  # no time info → include
    for t in times:
        mins = _time_str_to_minutes(t)
        if mins is None:
            continue
        if after_min is not None and mins < after_min:
            continue
        if before_min is not None and mins > before_min:
            continue
        return True
    return False


def get_just_opened_from_buckets(
    db: Session,
    limit_events: int = 500,
    date_filter: list[str] | None = None,
    time_slots: list[str] | None = None,
    party_sizes: list[int] | None = None,
    time_after_min: int | None = None,
    time_before_min: int | None = None,
    opened_within_minutes: int | None = None,
    opened_since: datetime | None = None,
) -> list[dict]:
    """
    Return same shape as legacy get_hot_drops for /just-opened: list of { date_str, venues, scanned_at }.
    Filters: date_filter, time_slots (bucket), party_sizes, and time range (minutes since midnight).
    time_after_min/time_before_min: only include venues with at least one slot in [after, before).
    opened_within_minutes: if set (e.g. 5), only include drop_events where opened_at >= now - N minutes.
    opened_since: if set (UTC datetime), only include drop_events where opened_at > opened_since (for polling "only new").
    in a previous scan but is no longer available (e.g. someone booked it), it is excluded.
    """
    today = window_start_date()
    bucket_ids = [bid for bid, _d, _t in all_bucket_ids(today)]
    bucket_rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
    curr_by_bucket: dict[str, set[str]] = {}
    for row in bucket_rows:
        # Exclude buckets not scanned recently so we don't pass stale results
        if not _is_bucket_fresh(row.scanned_at):
            curr_by_bucket[row.bucket_id] = set()
        else:
            curr_by_bucket[row.bucket_id] = _parse_slot_ids_json(row.prev_slot_ids_json)

    q = db.query(SlotAvailability).filter(SlotAvailability.state == "open").order_by(SlotAvailability.opened_at.desc())
    if opened_since is not None:
        if opened_since.tzinfo is None:
            opened_since = opened_since.replace(tzinfo=timezone.utc)
        q = q.filter(SlotAvailability.opened_at > opened_since)
        effective_limit = limit_events
    elif opened_within_minutes is not None and opened_within_minutes > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=opened_within_minutes)
        q = q.filter(SlotAvailability.opened_at >= cutoff)
        effective_limit = max(limit_events, 5000)
    else:
        effective_limit = limit_events
    events = q.limit(effective_limit).all()
    by_date: dict[str, dict] = {}
    # Per date: only add each venue once (by venue_id or name) so alert counts = unique restaurants
    seen_venue_key_per_date: dict[str, set[str]] = {}
    for r in events:
        curr_set = curr_by_bucket.get(r.bucket_id) or set()
        if r.slot_id not in curr_set:
            continue
        if time_slots and _bucket_time_slot(r.bucket_id) not in time_slots:
            continue
        date_str = r.bucket_id.split("_")[0] if "_" in r.bucket_id else ""
        if date_filter is not None and date_str not in date_filter:
            continue
        if date_str not in by_date:
            by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
            seen_venue_key_per_date[date_str] = set()
        payload = json.loads(r.payload_json) if r.payload_json else {}
        if not isinstance(payload, dict):
            continue
        venue_key = str(payload.get("venue_id") or payload.get("name") or "").strip()
        if venue_key and venue_key in seen_venue_key_per_date[date_str]:
            continue
        if venue_key:
            seen_venue_key_per_date[date_str].add(venue_key)
        # Always set detected_at so frontend can show "Added Xm ago". Prefer opened_at, fallback to payload.
        payload["detected_at"] = (
            r.opened_at.isoformat() if r.opened_at
            else payload.get("detected_at")
            or None
        )
        payload["name"] = r.venue_name or payload.get("name")
        if not _venue_matches_party_sizes(payload, party_sizes):
            continue
        if not _venue_in_time_range(payload, time_after_min, time_before_min):
            continue
        by_date[date_str]["venues"].append(payload)
    # scanned_at: max from discovery_buckets per date (one query for all dates)
    date_strs = list(by_date.keys())
    if date_strs:
        rows = (
            db.query(DiscoveryBucket.date_str, func.max(DiscoveryBucket.scanned_at))
            .filter(DiscoveryBucket.date_str.in_(date_strs))
            .group_by(DiscoveryBucket.date_str)
            .all()
        )
        for date_str, scanned_at in rows:
            if scanned_at and date_str in by_date:
                by_date[date_str]["scanned_at"] = scanned_at.isoformat()
    for date_str in date_strs:
        scan_iso = by_date[date_str].get("scanned_at")
        for venue in by_date[date_str]["venues"]:
            if venue.get("detected_at") is None and scan_iso:
                venue["detected_at"] = scan_iso
    return list(by_date.values())


def get_still_open_from_buckets(
    db: Session,
    today: date | None = None,
    date_filter: list[str] | None = None,
    time_slots: list[str] | None = None,
    party_sizes: list[int] | None = None,
    time_after_min: int | None = None,
    time_before_min: int | None = None,
    use_drop_events: bool = True,
    exclude_opened_within_minutes: int | None = None,
) -> list[dict]:
    """
    Slots that are in prev and not in baseline ("still open"). Same shape as get_just_opened_from_buckets.
    Baseline empty ([]) is valid: not-in-baseline then means all prev slots. Skip only when baseline not initialized (None).
    use_drop_events=True: build from DropEvent history (payload from DB). use_drop_events=False: compute prev−baseline per bucket and fetch payloads (no DropEvent dependency).
    exclude_opened_within_minutes: if set (e.g. 5), exclude events where opened_at is within the last N minutes so they only appear in "just opened", not here.
    """
    if today is None:
        today = window_start_date()
    bucket_ids = [bid for bid, _d, _t in all_bucket_ids(today)]
    bucket_rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
    prev_by_bucket: dict[str, set[str]] = {}
    baseline_by_bucket: dict[str, set[str]] = {}
    baseline_initialized_by_bucket: dict[str, bool] = {}
    for row in bucket_rows:
        # Exclude buckets not scanned recently so we don't pass stale results
        if not _is_bucket_fresh(row.scanned_at):
            prev_by_bucket[row.bucket_id] = set()
        else:
            prev_by_bucket[row.bucket_id] = _parse_slot_ids_json(row.prev_slot_ids_json)
        baseline_by_bucket[row.bucket_id] = _parse_slot_ids_json(row.baseline_slot_ids_json)
        baseline_initialized_by_bucket[row.bucket_id] = row.baseline_slot_ids_json is not None

    by_date: dict[str, dict] = {}

    if use_drop_events:
        q = (
            db.query(SlotAvailability)
            .filter(SlotAvailability.bucket_id.in_(bucket_ids), SlotAvailability.state == "open")
            .order_by(SlotAvailability.opened_at.desc())
        )
        if exclude_opened_within_minutes is not None and exclude_opened_within_minutes > 0:
            cutoff = datetime.now(timezone.utc) - timedelta(minutes=exclude_opened_within_minutes)
            q = q.filter(SlotAvailability.opened_at < cutoff)
        events = q.limit(STILL_OPEN_EVENTS_LIMIT).all()
        seen_slot_by_bucket: dict[str, set[str]] = {}
        seen_venue_key_per_date: dict[str, set[str]] = {}
        for r in events:
            prev_set = prev_by_bucket.get(r.bucket_id) or set()
            if not baseline_initialized_by_bucket.get(r.bucket_id):
                continue
            baseline_set = baseline_by_bucket.get(r.bucket_id) or set()
            if r.slot_id not in prev_set or r.slot_id in baseline_set:
                continue
            if time_slots and _bucket_time_slot(r.bucket_id) not in time_slots:
                continue
            seen = seen_slot_by_bucket.setdefault(r.bucket_id, set())
            if r.slot_id in seen:
                continue
            seen.add(r.slot_id)
            date_str = r.bucket_id.split("_")[0] if "_" in r.bucket_id else ""
            if date_filter is not None and date_str not in date_filter:
                continue
            if date_str not in by_date:
                by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
                seen_venue_key_per_date[date_str] = set()
            payload = json.loads(r.payload_json) if r.payload_json else {}
            if not isinstance(payload, dict):
                continue
            venue_key = str(payload.get("venue_id") or payload.get("name") or "").strip()
            if venue_key and venue_key in seen_venue_key_per_date[date_str]:
                continue
            if venue_key:
                seen_venue_key_per_date[date_str].add(venue_key)
            payload["detected_at"] = (
                r.opened_at.isoformat() if r.opened_at
                else payload.get("detected_at")
                or None
            )
            payload["name"] = r.venue_name or payload.get("name")
            payload["still_open"] = True
            if not _venue_matches_party_sizes(payload, party_sizes) or not _venue_in_time_range(payload, time_after_min, time_before_min):
                continue
            by_date[date_str]["venues"].append(payload)
    else:
        seen_venue_key_per_date_so: dict[str, set[str]] = {}
        for bid, date_str, time_slot in all_bucket_ids(today):
            if date_filter is not None and date_str not in date_filter:
                continue
            if time_slots and time_slot not in time_slots:
                continue
            if not baseline_initialized_by_bucket.get(bid):
                continue
            prev_set = prev_by_bucket.get(bid) or set()
            baseline_set = baseline_by_bucket.get(bid) or set()
            still_open_ids = prev_set - baseline_set
            if not still_open_ids:
                continue
            if date_str not in seen_venue_key_per_date_so:
                seen_venue_key_per_date_so[date_str] = set()
            rows = fetch_for_bucket(date_str, time_slot, party_sizes or PARTY_SIZES)
            for r in rows:
                if r["slot_id"] not in still_open_ids:
                    continue
                payload = dict(r.get("payload") or {})
                payload["name"] = r.get("venue_name") or payload.get("name")
                venue_key = str(payload.get("venue_id") or payload.get("name") or "").strip()
                if venue_key and venue_key in seen_venue_key_per_date_so[date_str]:
                    continue
                if venue_key:
                    seen_venue_key_per_date_so[date_str].add(venue_key)
                payload["still_open"] = True
                if not _venue_matches_party_sizes(payload, party_sizes) or not _venue_in_time_range(payload, time_after_min, time_before_min):
                    continue
                if date_str not in by_date:
                    by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
                by_date[date_str]["venues"].append(payload)

    for date_str in list(by_date.keys()):
        row = db.query(DiscoveryBucket).filter(DiscoveryBucket.date_str == date_str).order_by(DiscoveryBucket.scanned_at.desc().nullslast()).first()
        if row and row.scanned_at:
            by_date[date_str]["scanned_at"] = row.scanned_at.isoformat()
        scan_iso = by_date[date_str].get("scanned_at")
        for venue in by_date[date_str]["venues"]:
            if venue.get("detected_at") is None and scan_iso:
                venue["detected_at"] = scan_iso
    return list(by_date.values())


def get_last_scan_info_buckets(db: Session, today: date) -> dict:
    """Last scan time and total slots across buckets (for API compatibility)."""
    row = db.query(DiscoveryBucket).filter(DiscoveryBucket.date_str >= today.isoformat()).order_by(DiscoveryBucket.scanned_at.desc().nullslast()).first()
    total = 0
    for r in db.query(DiscoveryBucket).filter(DiscoveryBucket.date_str >= today.isoformat()).all():
        total += len(_parse_slot_ids_json(r.prev_slot_ids_json))
    return {
        "last_scan_at": row.scanned_at.isoformat() if row and row.scanned_at else None,
        "total_venues_scanned": total,
    }


def get_feed_item_debug(
    db: Session,
    event_id: int | str | None = None,
    slot_id: str | None = None,
    bucket_id: str | None = None,
    fetch_curr: bool = False,
) -> dict | None:
    """
    Why is this in the feed? For a drop (by event_id "bucket_id|slot_id" or slot_id+bucket_id), return
    membership in baseline/prev/curr and a reason.
    """
    event = None
    if event_id is not None:
        eid = str(event_id).strip()
        if "|" in eid:
            parts = eid.split("|", 1)
            bucket_id = parts[0]
            slot_id = parts[1] if len(parts) > 1 else None
        elif isinstance(event_id, int) or (eid.isdigit() and eid):
            event = db.query(DropEvent).filter(DropEvent.id == int(event_id if isinstance(event_id, int) else eid)).first()
    if event is None and slot_id and bucket_id:
        event = (
            db.query(SlotAvailability)
            .filter(SlotAvailability.slot_id == slot_id, SlotAvailability.bucket_id == bucket_id)
            .first()
        )
    if not event:
        return None
    bucket_row = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id == event.bucket_id).first()
    baseline_set = _parse_slot_ids_json(bucket_row.baseline_slot_ids_json) if bucket_row else set()
    prev_set = _parse_slot_ids_json(bucket_row.prev_slot_ids_json) if bucket_row else set()
    in_baseline = event.slot_id in baseline_set
    in_prev = event.slot_id in prev_set
    in_curr: bool | None = None
    if fetch_curr and bucket_row and "_" in getattr(event, "bucket_id", ""):
        bid = getattr(event, "bucket_id", "")
        parts = bid.split("_", 1)
        date_str = parts[0]
        time_slot = parts[1] if len(parts) > 1 else "19:00"
        prov = (getattr(event, "provider", None) or "resy").strip() or "resy"
        rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=prov)
        curr_set = {r["slot_id"] for r in rows}
        in_curr = event.slot_id in curr_set
    # Reason: if currently in baseline/prev that's a signal (baseline = should not have been emitted)
    if in_baseline:
        reason = "WARNING: slot_id is in baseline now — should not have been emitted (baseline echo bug)"
    elif in_prev:
        reason = "in prev now (slot was opened vs prev and new vs baseline when emitted; may have stayed open)"
    else:
        reason = "opened_vs_prev_and_new_vs_baseline (not in baseline or prev now)"
    event_id_out = getattr(event, "id", None)
    if event_id_out is None:
        event_id_out = f"{event.bucket_id}|{event.slot_id}"
    return {
        "event_id": event_id_out,
        "slot_id": event.slot_id,
        "bucket_id": event.bucket_id,
        "venue_name": getattr(event, "venue_name", None),
        "venue_id": getattr(event, "venue_id", None),
        "in_baseline": in_baseline,
        "in_prev": in_prev,
        "in_curr": in_curr,
        "emitted_at": (event.opened_at.isoformat() if event.opened_at else None) if hasattr(event, "opened_at") else None,
        "reason": reason,
        "baseline_count": len(baseline_set),
        "prev_count": len(prev_set),
    }


def get_discovery_debug_buckets(db: Session, today: date | None = None) -> dict:
    """Debug view for bucket pipeline: bucket_health, recent drops sample, summary."""
    if today is None:
        today = window_start_date()
    bucket_health = get_bucket_health(db, today)
    # Recent drops sample: name + minutes_ago (from projection)
    recent = (
        db.query(SlotAvailability)
        .filter(SlotAvailability.state == "open")
        .order_by(SlotAvailability.opened_at.desc())
        .limit(15)
        .all()
    )
    now = datetime.now(timezone.utc)
    hot_drops_sample = []
    for r in recent:
        opened = getattr(r, "opened_at", None)
        opened = opened.replace(tzinfo=timezone.utc) if opened and not getattr(opened, "tzinfo", None) else opened
        mins = int((now - opened).total_seconds() / 60) if opened else None
        hot_drops_sample.append({"name": getattr(r, "venue_name", None) or getattr(r, "venue_id", None) or "?", "minutes_ago": mins})
    info = get_last_scan_info_buckets(db, today)
    return {
        "bucket_health": bucket_health,
        "summary": {
            "last_scan_at": info.get("last_scan_at"),
            "total_venues_scanned": info.get("total_venues_scanned", 0),
            "buckets_count": len(bucket_health),
        },
        "hot_drops_sample": hot_drops_sample,
    }

"""
Discovery: per-bucket state and drop formula (scalable pattern).

- Bucket = QueryKey (date_str, time_slot). We compare only to previous snapshot, not to initial baseline.
- Each poll: curr = fetch from Resy; added = curr - prev; update prev = curr. Baseline is only for the first prev.
- We write all added to SlotAvailability (feed shows them). We only create DropEvent for added slots not in
  "notified recently" (TTL dedupe: same bucket+slot within NOTIFIED_DEDUPE_MINUTES → no duplicate notification).
- Closed: prev - curr → mark closed in SlotAvailability and sessions.
"""
import hashlib
import json
import logging
import uuid
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone
from typing import Callable

from sqlalchemy import func, text, tuple_
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.constants import (
    DISCOVERY_JUST_OPENED_LIMIT,
    DISCOVERY_STILL_OPEN_LIMIT,
    DISCOVERY_MAX_VENUES_PER_DATE as MAX_VENUES_PER_DATE_CONF,
    DROP_EVENTS_RETENTION_DAYS,
    METRICS_RETENTION_DAYS,
    VENUES_RETENTION_DAYS,
)
from app.core.discovery_config import (
    DISCOVERY_DATE_TIMEZONE,
    DISCOVERY_MAX_CONCURRENT_BUCKETS,
    DISCOVERY_PARTY_SIZES,
    DISCOVERY_TIME_SLOTS,
    DISCOVERY_WINDOW_DAYS,
    NOTIFIED_DEDUPE_MINUTES,
    NOTIFICATIONS_RETENTION_DAYS,
)
from app.db.session import SessionLocal


def window_start_date() -> date:
    """
    First day of the 14-day discovery window, in the app's date timezone (e.g. America/New_York).
    We start the window one day before "today" in that TZ so that when a user in an earlier
    timezone (e.g. Pacific) has "today" in their date picker, we still have a bucket for that date
    even though in ET it may already be the next day. Pruning still uses this same date, so we
    keep buckets for window_start through window_start+13 (14 days total).
    """
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(DISCOVERY_DATE_TIMEZONE)
    except Exception:
        tz = None
    if tz is not None:
        now = datetime.now(tz)
        # Include previous calendar day so West Coast "today" has a bucket when ET is already tomorrow
        return now.date() - timedelta(days=1)
    return date.today() - timedelta(days=1)

from app.models.availability_state import AvailabilityState
from app.models.discovery_bucket import DiscoveryBucket
from app.models.drop_event import DropEvent
from app.models.slot_availability import SlotAvailability
from app.models.user_notification import UserNotification
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

MAX_PAGES = 2
PER_PAGE = 200
# Batch size for bulk inserts in run_poll_for_bucket (avoids 10k+ round-trips per bucket)
POLL_BATCH_SIZE = 500
# Buckets not scanned within this many hours are excluded from just-opened and still-open (avoid passing stale data)
STALE_BUCKET_HOURS = 4
# Cap slot_availability rows for still-open (use central constant for scalability)
STILL_OPEN_EVENTS_LIMIT = DISCOVERY_STILL_OPEN_LIMIT
# Cap venues per date in just-opened and still-open responses
MAX_VENUES_PER_DATE = MAX_VENUES_PER_DATE_CONF


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
    bid = bucket_id(date_str, time_slot)
    try:
        results = prov.search_availability(date_str, time_slot, party_sizes)
    except Exception as e:
        logger.warning("Provider %s search failed bucket=%s: %s", provider, bid, e)
        return []
    rows = [r.to_row() for r in results]
    if not rows:
        logger.debug("Provider %s returned 0 slots for bucket=%s (date=%s time_slot=%s) — baseline will be 0", provider, bid, date_str, time_slot)
    return rows


def _parse_slot_ids_json(js: str | None) -> set[str]:
    if not js:
        return set()
    try:
        arr = json.loads(js)
        return set(str(x) for x in arr if x)
    except (TypeError, json.JSONDecodeError):
        return set()


def _time_bucket_from_slot(time_slot: str) -> str:
    """Map bucket time_slot to time_bucket: 20:30 = prime (8:30 PM), 15:00 = off_peak."""
    return "prime" if time_slot == "20:30" else "off_peak"


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


def _build_slot_availability_row(
    bid: str,
    sid: str,
    r: dict | None,
    date_str: str,
    now: datetime,
    time_bucket_val: str,
    provider: str,
    run_id: str | None = None,
) -> dict:
    """Build one SlotAvailability row dict (open state). Used by bootstrap and drops."""
    payload = r.get("payload") if r else {}
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
    return {
        "bucket_id": bid,
        "slot_id": sid,
        "state": "open",
        "opened_at": now,
        "last_seen_at": now,
        "venue_id": r.get("venue_id") if r else None,
        "venue_name": r.get("venue_name") if r else None,
        "payload_json": json.dumps(r.get("payload") or {}) if r else "{}",
        "run_id": run_id or str(uuid.uuid4()),
        "updated_at": now,
        "time_bucket": time_bucket_val,
        "slot_date": slot_date_val,
        "slot_time": slot_time_val,
        "provider": provider,
        "neighborhood": neighborhood_val,
        "price_range": price_range_val,
    }


def _bootstrap_slot_availability(
    db: Session,
    bid: str,
    date_str: str,
    time_slot: str,
    rows: list[dict],
    curr_set: set[str],
    now: datetime,
    provider: str,
) -> None:
    """Write all curr_set to SlotAvailability (open). Used when creating a new bucket or when baseline was None."""
    if not curr_set:
        return
    run_id = str(uuid.uuid4())
    time_bucket_val = _time_bucket_from_slot(time_slot)
    by_slot = {r["slot_id"]: r for r in rows}
    bootstrap_rows = [
        _build_slot_availability_row(bid, sid, by_slot.get(sid), date_str, now, time_bucket_val, provider, run_id)
        for sid in curr_set
        if by_slot.get(sid) is not None
    ]
    for i in range(0, len(bootstrap_rows), POLL_BATCH_SIZE):
        chunk = bootstrap_rows[i : i + POLL_BATCH_SIZE]
        ins = pg_insert(SlotAvailability).values(chunk)
        db.execute(ins.on_conflict_do_update(
            index_elements=["bucket_id", "slot_id"],
            set_={
                SlotAvailability.state: ins.excluded.state,
                SlotAvailability.opened_at: ins.excluded.opened_at,
                SlotAvailability.last_seen_at: ins.excluded.last_seen_at,
                SlotAvailability.venue_id: ins.excluded.venue_id,
                SlotAvailability.venue_name: ins.excluded.venue_name,
                SlotAvailability.payload_json: ins.excluded.payload_json,
                SlotAvailability.run_id: ins.excluded.run_id,
                SlotAvailability.updated_at: ins.excluded.updated_at,
                SlotAvailability.time_bucket: ins.excluded.time_bucket,
                SlotAvailability.slot_date: ins.excluded.slot_date,
                SlotAvailability.slot_time: ins.excluded.slot_time,
                SlotAvailability.provider: ins.excluded.provider,
                SlotAvailability.neighborhood: ins.excluded.neighborhood,
                SlotAvailability.price_range: ins.excluded.price_range,
                SlotAvailability.closed_at: None,
            },
            where=text("slot_availability.updated_at < excluded.updated_at"),
        ))


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
    Does NOT write to slot_availability or availability_state (no state/metrics from baseline).
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
        _bootstrap_slot_availability(db, bid, date_str, time_slot, rows, curr_set, now, provider)
        db.commit()
        return 0, len(curr_set), {"B": len(curr_set), "P": len(curr_set), "C": len(curr_set), "baseline_ready": True, "emitted": 0, "baseline_echo": 0, "prev_echo": 0}

    baseline_js = bucket_row.baseline_slot_ids_json
    if baseline_js is None:
        js = json.dumps(sorted(curr_set))
        bucket_row.baseline_slot_ids_json = js
        bucket_row.prev_slot_ids_json = js
        bucket_row.scanned_at = now
        n = len(curr_set)
        if n > 0:
            _bootstrap_slot_availability(db, bid, date_str, time_slot, rows, curr_set, now, provider)
            logger.info("Bucket %s: initialized baseline (was None), %s slots, bootstrap wrote to slot_availability", bid, n)
        else:
            logger.warning(
                "Bucket %s: initialized baseline with 0 slots — Resy returned no availability for date=%s time_slot=%s. Check GET /chat/watches/resy-test and RESY_API_KEY/RESY_AUTH_TOKEN.",
                bid, date_str, time_slot,
            )
        db.commit()
        return 0, len(curr_set), {"B": len(curr_set), "P": len(curr_set), "C": len(curr_set), "baseline_ready": True, "emitted": 0, "baseline_echo": 0, "prev_echo": 0}

    prev_set = _parse_slot_ids_json(bucket_row.prev_slot_ids_json)
    B = len(_parse_slot_ids_json(baseline_js))
    P, C = len(prev_set), len(curr_set)

    # New since last poll only (no comparison to initial baseline forever)
    added = curr_set - prev_set
    drops = added

    # Only treat as "just opened" (DropEvent) venues that had ZERO slots in the previous poll.
    # Venues that had availability at other times and gained more times are not "drops" for the feed.
    run_id = str(uuid.uuid4())
    time_bucket_val = _time_bucket_from_slot(time_slot)
    by_slot = {r["slot_id"]: r for r in rows}
    prev_venue_ids: set[str] = set()
    if prev_set:
        prev_venue_ids = {
            str(r[0])
            for r in db.query(SlotAvailability.venue_id)
            .filter(
                SlotAvailability.bucket_id == bid,
                SlotAvailability.slot_id.in_(list(prev_set)),
                SlotAvailability.venue_id.isnot(None),
            )
            .distinct()
            .all()
            if r[0] is not None
        }
    drops_venue_zero = {
        sid
        for sid in drops
        if str((by_slot.get(sid) or {}).get("venue_id") or "") not in prev_venue_ids
    }

    # TTL dedupe: don't create DropEvent if we already notified for this (bucket_id, slot_id) recently
    cutoff = now - timedelta(minutes=NOTIFIED_DEDUPE_MINUTES)
    recently_notified = {
        row[0]
        for row in db.query(DropEvent.slot_id).filter(
            DropEvent.bucket_id == bid,
            DropEvent.opened_at >= cutoff,
        ).distinct().all()
    }
    drops_to_emit = drops_venue_zero - recently_notified

    # --- Projection: all added go to SlotAvailability (feed); only drops_venue_zero get a DropEvent (venue had 0 before) ---
    slot_rows = [
        _build_slot_availability_row(bid, sid, by_slot.get(sid), date_str, now, time_bucket_val, provider, run_id)
        for sid in drops
    ]
    drop_rows = []
    for sid in drops_to_emit:
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
        drop_rows.append({
            "bucket_id": bid,
            "slot_id": sid,
            "opened_at": now,
            "venue_id": r.get("venue_id") if r else None,
            "venue_name": r.get("venue_name") if r else None,
            "payload_json": json.dumps(r["payload"]) if r else None,
            "dedupe_key": f"{bid}|{sid}|{now.strftime('%Y-%m-%dT%H:%M')}",
            "time_bucket": time_bucket_val,
            "slot_date": slot_date_val,
            "slot_time": slot_time_val,
            "provider": provider,
            "neighborhood": neighborhood_val,
            "price_range": price_range_val,
        })

    # Bulk insert SlotAvailability in batches (use excluded for conflict update so new row wins)
    for i in range(0, len(slot_rows), POLL_BATCH_SIZE):
        chunk = slot_rows[i : i + POLL_BATCH_SIZE]
        ins = pg_insert(SlotAvailability).values(chunk)
        db.execute(ins.on_conflict_do_update(
            index_elements=["bucket_id", "slot_id"],
            set_={
                SlotAvailability.state: ins.excluded.state,
                SlotAvailability.opened_at: ins.excluded.opened_at,
                SlotAvailability.last_seen_at: ins.excluded.last_seen_at,
                SlotAvailability.venue_id: ins.excluded.venue_id,
                SlotAvailability.venue_name: ins.excluded.venue_name,
                SlotAvailability.payload_json: ins.excluded.payload_json,
                SlotAvailability.run_id: ins.excluded.run_id,
                SlotAvailability.updated_at: ins.excluded.updated_at,
                SlotAvailability.time_bucket: ins.excluded.time_bucket,
                SlotAvailability.slot_date: ins.excluded.slot_date,
                SlotAvailability.slot_time: ins.excluded.slot_time,
                SlotAvailability.provider: ins.excluded.provider,
                SlotAvailability.neighborhood: ins.excluded.neighborhood,
                SlotAvailability.price_range: ins.excluded.price_range,
                SlotAvailability.closed_at: None,
            },
            where=text("slot_availability.updated_at < excluded.updated_at"),
        ))
    emitted = len(drop_rows)  # DropEvents created this run (excl. TTL-deduped)

    # Bulk insert DropEvent in batches (on_conflict_do_nothing)
    for i in range(0, len(drop_rows), POLL_BATCH_SIZE):
        chunk = drop_rows[i : i + POLL_BATCH_SIZE]
        try:
            db.execute(
                pg_insert(DropEvent).values(chunk).on_conflict_do_nothing(index_elements=["dedupe_key"])
            )
        except Exception as e:
            logger.debug("DropEvent batch insert skip: %s", e)

    # availability_state: one row per (bucket, slot). Upsert on open (no history — avoids write amplification).
    existing_slot_ids = {
        row[0]
        for row in db.query(AvailabilityState.slot_id).filter(
            AvailabilityState.bucket_id == bid,
            AvailabilityState.closed_at.is_(None),
        ).all()
    }
    state_rows_to_upsert = []
    for sid in drops:
        if sid in existing_slot_ids:
            continue
        existing_slot_ids.add(sid)
        r = by_slot.get(sid)
        payload = r.get("payload") if r else None
        slot_date_val, _ = _slot_date_time_from_payload(payload, date_str)
        state_rows_to_upsert.append({
            "bucket_id": bid,
            "slot_id": sid,
            "opened_at": now,
            "closed_at": None,
            "venue_id": r.get("venue_id") if r else None,
            "venue_name": r.get("venue_name") if r else None,
            "slot_date": slot_date_val,
            "provider": provider,
        })
    for i in range(0, len(state_rows_to_upsert), POLL_BATCH_SIZE):
        chunk = state_rows_to_upsert[i : i + POLL_BATCH_SIZE]
        stmt = pg_insert(AvailabilityState).values(chunk)
        db.execute(stmt.on_conflict_do_update(
            index_elements=["bucket_id", "slot_id"],
            set_={
                AvailabilityState.opened_at: stmt.excluded.opened_at,
                AvailabilityState.closed_at: None,
                AvailabilityState.venue_id: stmt.excluded.venue_id,
                AvailabilityState.venue_name: stmt.excluded.venue_name,
                AvailabilityState.slot_date: stmt.excluded.slot_date,
                AvailabilityState.provider: stmt.excluded.provider,
            },
        ))
    # Close all slots that are open in DB but not in curr_set (one query + bulk update + sessions)
    to_aggregate: list[ClosedEventData] = []
    closed_rows = (
        db.query(SlotAvailability)
        .filter(
            SlotAvailability.bucket_id == bid,
            SlotAvailability.state == "open",
            SlotAvailability.slot_id.notin_(list(curr_set)),
        )
        .all()
    )
    closed_slot_ids = {row.slot_id for row in closed_rows}
    if closed_slot_ids:
        db.query(SlotAvailability).filter(
            SlotAvailability.bucket_id == bid,
            SlotAvailability.slot_id.in_(closed_slot_ids),
        ).update(
            {
                SlotAvailability.state: "closed",
                SlotAvailability.closed_at: now,
                SlotAvailability.last_seen_at: now,
                SlotAvailability.run_id: run_id,
                SlotAvailability.updated_at: now,
            },
            synchronize_session=False,
        )
        for row in closed_rows:
            opened_at_dt = row.opened_at.replace(tzinfo=timezone.utc) if row.opened_at and row.opened_at.tzinfo is None else row.opened_at
            duration_seconds = int((now - opened_at_dt).total_seconds()) if opened_at_dt else 0
            if duration_seconds < 0:
                continue
            open_state = (
                db.query(AvailabilityState)
                .filter(
                    AvailabilityState.bucket_id == bid,
                    AvailabilityState.slot_id == row.slot_id,
                    AvailabilityState.closed_at.is_(None),
                )
                .first()
            )
            if open_state:
                open_state.closed_at = now
                open_state.duration_seconds = duration_seconds
                to_aggregate.append(ClosedEventData(
                    venue_id=row.venue_id,
                    venue_name=row.venue_name,
                    drop_duration_seconds=duration_seconds,
                    slot_date=row.slot_date or date_str,
                    bucket_id=bid,
                    session_id=open_state.id,
                ))

    bucket_row.prev_slot_ids_json = json.dumps(sorted(curr_set))
    bucket_row.scanned_at = now

    # Remove drop_events for closed slots that have already been pushed (keeps table bounded)
    if closed_slot_ids:
        n_dropped = (
            db.query(DropEvent)
            .filter(
                DropEvent.bucket_id == bid,
                DropEvent.slot_id.in_(closed_slot_ids),
                DropEvent.push_sent_at.isnot(None),
            )
            .delete(synchronize_session=False)
        )
        if n_dropped:
            logger.debug("Pruned %s drop_events (closed+push_sent) for bucket %s", n_dropped, bid)

    stats = {
        "B": B,
        "P": P,
        "C": C,
        "added": len(drops),
        "deduped": len(drops) - len(drops_to_emit),
        "emitted": emitted,
        "closed_emitted": len(to_aggregate),
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
            # Delete closed rows from availability_state so table stays small (only open slots).
            state_ids = [e.session_id for e in to_aggregate if getattr(e, "session_id", None) is not None]
            if state_ids:
                db.query(AvailabilityState).filter(AvailabilityState.id.in_(state_ids)).delete(synchronize_session=False)
                db.commit()
        except Exception as e:
            logger.warning("Aggregate closed events failed bucket=%s: %s", bid, e)

    logger.info(
        "bucket=%s B=%s P=%s C=%s | added=%s deduped=%s emitted=%s closed=%s",
        bid, B, P, C, len(drops), len(drops) - len(drops_to_emit), emitted, len(to_aggregate),
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
    """
    Keep drop_events bounded: (1) remove rows for buckets before today;
    (2) remove rows older than DROP_EVENTS_RETENTION_DAYS that have already been pushed.
    Only deletes pushed rows so the push job never loses unsent events.
    """
    today_str = today.isoformat()
    cutoff_bucket = f"{today_str}_15:00"
    n_bucket = db.query(DropEvent).filter(DropEvent.bucket_id < cutoff_bucket).delete(synchronize_session=False)
    # Time-based: drop old events that we've already sent (push_sent_at set)
    cutoff_time = datetime.now(timezone.utc) - timedelta(days=DROP_EVENTS_RETENTION_DAYS)
    n_time = (
        db.query(DropEvent)
        .filter(DropEvent.opened_at < cutoff_time, DropEvent.push_sent_at.isnot(None))
        .delete(synchronize_session=False)
    )
    db.commit()
    n = n_bucket + n_time
    if n:
        logger.info(
            "Pruned %s drop_events (bucket<%s: %s, opened_at>%s days + pushed: %s)",
            n,
            today_str,
            n_bucket,
            DROP_EVENTS_RETENTION_DAYS,
            n_time,
        )
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
    """No-op: we use availability_state now. Kept for API compatibility (daily job)."""
    return 0


def prune_old_availability_state(db: Session, today: date) -> int:
    """Remove availability_state rows for buckets before today (stale open slots)."""
    today_str = today.isoformat()
    cutoff = f"{today_str}_15:00"
    n = db.query(AvailabilityState).filter(AvailabilityState.bucket_id < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s availability_state (bucket_id < %s)", n, today_str)
    return n


def prune_old_notifications(db: Session) -> int:
    """Remove user_notifications older than NOTIFICATIONS_RETENTION_DAYS (scheduled daily, not in hot path)."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=NOTIFICATIONS_RETENTION_DAYS)
    n = db.query(UserNotification).filter(UserNotification.created_at < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s user_notifications (created_at > %s days)", n, NOTIFICATIONS_RETENTION_DAYS)
    return n


def prune_old_venue_rolling_metrics(db: Session, today: date | None = None, keep_days: int = 60) -> int:
    """Remove venue_rolling_metrics older than keep_days so the table does not grow unbounded."""
    from app.models.venue_rolling_metrics import VenueRollingMetrics
    ref = today or date.today()
    cutoff = ref - timedelta(days=keep_days)
    n = db.query(VenueRollingMetrics).filter(VenueRollingMetrics.as_of_date < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s venue_rolling_metrics (as_of_date < %s)", n, cutoff)
    return n


def prune_old_venue_metrics(db: Session, today: date | None = None, keep_days: int | None = None) -> int:
    """Remove venue_metrics older than keep_days so the table does not grow unbounded."""
    from app.models.venue_metrics import VenueMetrics
    ref = today or date.today()
    keep = keep_days if keep_days is not None else METRICS_RETENTION_DAYS
    cutoff = ref - timedelta(days=keep)
    n = db.query(VenueMetrics).filter(VenueMetrics.window_date < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s venue_metrics (window_date < %s)", n, cutoff)
    return n


def prune_old_market_metrics(db: Session, today: date | None = None, keep_days: int | None = None) -> int:
    """Remove market_metrics older than keep_days so the table does not grow unbounded."""
    from app.models.market_metrics import MarketMetrics
    ref = today or date.today()
    keep = keep_days if keep_days is not None else METRICS_RETENTION_DAYS
    cutoff = ref - timedelta(days=keep)
    n = db.query(MarketMetrics).filter(MarketMetrics.window_date < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s market_metrics (window_date < %s)", n, cutoff)
    return n


def prune_old_venues(db: Session, keep_days: int | None = None) -> int:
    """Remove venues not seen in keep_days so the table does not grow unbounded."""
    keep = keep_days if keep_days is not None else VENUES_RETENTION_DAYS
    cutoff = datetime.now(timezone.utc) - timedelta(days=keep)
    n = db.query(Venue).filter(Venue.last_seen_at < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s venues (last_seen_at < %s days)", n, keep)
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
    Each bucket is re-scanned after cooldown (default 10s); tick every 3s dispatches ready buckets. Failed buckets are retried once (sequential).
    Returns { "buckets_polled", "drops_emitted", "last_scan_at", "errors", "invariants" }.
    """
    ensure_buckets(db, today)
    buckets = list(all_bucket_ids(today))
    drops_emitted = 0
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
    return {
        "buckets_polled": len(buckets) - len(errors),
        "drops_emitted": drops_emitted,
        "last_scan_at": last_scan_at,
        "errors": error_ids,
        "invariants": {
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


def get_just_opened_from_buckets(
    db: Session,
    limit_events: int = 500,
    date_filter: list[str] | None = None,
    time_slots: list[str] | None = None,
    party_sizes: list[int] | None = None,
    opened_within_minutes: int | None = None,
    opened_since: datetime | None = None,
) -> list[dict]:
    """
    Just opened: slots we actually detected as new (curr - prev), still open.
    We base this on DropEvent, not SlotAvailability.opened_at, so bootstrap/first-poll
    slots (which never get a DropEvent) do not appear as "new" — only real new drops do.
    Returns list of { date_str, venues, scanned_at }. Optional filters: date_filter, time_slots (bucket), party_sizes.
    """
    now = datetime.now(timezone.utc)
    if opened_since is not None:
        if opened_since.tzinfo is None:
            opened_since = opened_since.replace(tzinfo=timezone.utc)
        cutoff = opened_since
    elif opened_within_minutes is not None and opened_within_minutes > 0:
        cutoff = now - timedelta(minutes=opened_within_minutes)
    else:
        cutoff = now - timedelta(minutes=10)
    # Only slots we emitted as "new" (have a DropEvent in the window); then require still open in SlotAvailability
    drop_q = (
        db.query(DropEvent.bucket_id, DropEvent.slot_id)
        .filter(DropEvent.opened_at >= cutoff)
        .distinct()
        .limit(limit_events)
    )
    drop_pairs = [(r.bucket_id, r.slot_id) for r in drop_q.all()]
    if not drop_pairs:
        return []
    # Resolve to SlotAvailability rows that are still open (slot may have closed since drop)
    events = (
        db.query(SlotAvailability)
        .filter(
            SlotAvailability.state == "open",
            tuple_(SlotAvailability.bucket_id, SlotAvailability.slot_id).in_(drop_pairs),
        )
        .order_by(SlotAvailability.opened_at.desc())
        .limit(limit_events)
        .all()
    )

    # Group by (date_str, venue_key) so we merge all slots per venue into one venue with availability_times[]
    by_date: dict[str, dict] = {}
    by_venue: dict[str, dict[str, list[tuple]]] = {}  # by_date[date_str][venue_key] = [(r, payload), ...]
    for r in events:
        if time_slots and _bucket_time_slot(r.bucket_id) not in time_slots:
            continue
        date_str = r.bucket_id.split("_")[0] if "_" in r.bucket_id else ""
        if date_filter is not None and date_str not in date_filter:
            continue
        if date_str not in by_date:
            by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
            by_venue[date_str] = {}
        payload = json.loads(r.payload_json) if r.payload_json else {}
        if not isinstance(payload, dict):
            continue
        venue_key = str(payload.get("venue_id") or payload.get("name") or "").strip() or "unknown"
        if not _venue_matches_party_sizes(payload, party_sizes):
            continue
        if venue_key not in by_venue[date_str]:
            by_venue[date_str][venue_key] = []
        payload["detected_at"] = r.opened_at.isoformat() if r.opened_at else payload.get("detected_at")
        payload["name"] = r.venue_name or payload.get("name")
        by_venue[date_str][venue_key].append((r, payload))

    # Build one venue per (date_str, venue_key) with availability_times = all slot times from all rows
    for date_str in by_venue:
        for venue_key, row_payloads in by_venue[date_str].items():
            _, first_payload = row_payloads[0]
            availability_times = sorted({(r.slot_time or "").strip() for r, _ in row_payloads if (r.slot_time or "").strip()})
            if not availability_times:
                # fallback: first payload may have one time from Resy
                availability_times = list(first_payload.get("availability_times") or [])
            first_payload["availability_times"] = availability_times
            by_date[date_str]["venues"].append(first_payload)

    for date_str in by_date:
        venues = by_date[date_str]["venues"]
        if len(venues) > MAX_VENUES_PER_DATE:
            by_date[date_str]["venues"] = venues[:MAX_VENUES_PER_DATE]
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
    exclude_opened_within_minutes: int | None = None,
) -> list[dict]:
    """
    Still open: slots that are currently open but not in "just opened" (no recent DropEvent).
    Includes bootstrap slots (no DropEvent) and slots that dropped more than N min ago.
    Same shape as get_just_opened. Optional filters: date_filter, time_slots, party_sizes.
    """
    q = db.query(SlotAvailability).filter(SlotAvailability.state == "open").order_by(SlotAvailability.opened_at.desc())
    if exclude_opened_within_minutes is not None and exclude_opened_within_minutes > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=exclude_opened_within_minutes)
        # Exclude slots that have a DropEvent in the window (those appear in "just opened")
        recent_drop_pairs = (
            db.query(DropEvent.bucket_id, DropEvent.slot_id)
            .filter(DropEvent.opened_at >= cutoff)
            .distinct()
            .all()
        )
        recent_set = [(r.bucket_id, r.slot_id) for r in recent_drop_pairs]
        if recent_set:
            q = q.filter(~tuple_(SlotAvailability.bucket_id, SlotAvailability.slot_id).in_(recent_set))
    events = q.limit(STILL_OPEN_EVENTS_LIMIT).all()

    by_date: dict[str, dict] = {}
    by_venue: dict[str, dict[str, list[tuple]]] = {}
    for r in events:
        if time_slots and _bucket_time_slot(r.bucket_id) not in time_slots:
            continue
        date_str = r.bucket_id.split("_")[0] if "_" in r.bucket_id else ""
        if date_filter is not None and date_str not in date_filter:
            continue
        if date_str not in by_date:
            by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
            by_venue[date_str] = {}
        payload = json.loads(r.payload_json) if r.payload_json else {}
        if not isinstance(payload, dict):
            continue
        venue_key = str(payload.get("venue_id") or payload.get("name") or "").strip() or "unknown"
        if not _venue_matches_party_sizes(payload, party_sizes):
            continue
        if venue_key not in by_venue[date_str]:
            by_venue[date_str][venue_key] = []
        payload["detected_at"] = r.opened_at.isoformat() if r.opened_at else payload.get("detected_at")
        payload["name"] = r.venue_name or payload.get("name")
        payload["still_open"] = True
        by_venue[date_str][venue_key].append((r, payload))

    for date_str in by_venue:
        for venue_key, row_payloads in by_venue[date_str].items():
            _, first_payload = row_payloads[0]
            availability_times = sorted({(r.slot_time or "").strip() for r, _ in row_payloads if (r.slot_time or "").strip()})
            if not availability_times:
                availability_times = list(first_payload.get("availability_times") or [])
            first_payload["availability_times"] = availability_times
            by_date[date_str]["venues"].append(first_payload)

    for date_str in by_date:
        venues = by_date[date_str]["venues"]
        if len(venues) > MAX_VENUES_PER_DATE:
            by_date[date_str]["venues"] = venues[:MAX_VENUES_PER_DATE]
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
        time_slot = parts[1] if len(parts) > 1 else "20:30"
        prov = (getattr(event, "provider", None) or "resy").strip() or "resy"
        rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=prov)
        curr_set = {r["slot_id"] for r in rows}
        in_curr = event.slot_id in curr_set
    # Reason: if currently in baseline/prev that's a signal (baseline = should not have been emitted)
    if in_baseline:
        reason = "WARNING: slot_id is in baseline now — should not have been emitted (baseline echo bug)"
    elif in_prev:
        reason = "in prev now (slot was added when emitted; may have stayed open)"
    else:
        reason = "added since last poll (not in prev now; may have closed or TTL deduped)"
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

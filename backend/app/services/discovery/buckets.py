"""
Discovery: per-bucket state and drop formula (scalable pattern).

**Product rule (what counts as a “drop”):** we only care when a venue had **no** reservation
times showing in our **baseline** snapshot (for us, that place was fully booked / not bookable
in that scan). We do **not** care about “another time opened” at a venue that **already** had
at least one time in baseline — that is not a reopening story.

**Mechanics:** Baseline = first successful snapshot; prev = last poll. Slot-level:
`added = curr − prev`, `drops = added − baseline_set` (new slot lines since baseline, deduped
by prev). **Venue gate:** `baseline_venue_ids_json` lists every venue that had ≥1 slot in
baseline; any drop candidate whose venue is in that set is discarded (including when Resy
returns a different time string so `slot_id` hashes don’t match baseline).

We write slot-level adds to SlotAvailability. DropEvents (after TTL/dup_open dedupe) only for
candidates that pass the venue gate.
- DropEvent rows set user_facing_opened_at (same instant as opened_at / slot_availability.opened_at), eligibility
  evidence from prev/baseline geometry, prior_prev_slot_count, and prior_snapshot_included_slot=false for adds.
- successful_poll_count increments on each completed baseline init or full poll (not on advisory lock skip).
- Closed: prev - curr → remove SlotAvailability rows and **all** drop_events for that (bucket_id, slot_id).
- **Orphan drop_events** (no matching open `slot_availability` row) are pruned periodically and daily — they should
  not exist if close-path runs; pruning reclaims leaks. **venues.last_drop_opened_at** holds last emit time so we
  do not need to scan `drop_events` for follow status.
"""
import hashlib
import json
import logging
import uuid
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone
from typing import Callable
from zoneinfo import ZoneInfo

from sqlalchemy import and_, func, text, tuple_
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.constants import (
    DISCOVERY_JUST_OPENED_LIMIT,
    DISCOVERY_STILL_OPEN_LIMIT,
    DISCOVERY_MAX_VENUES_PER_DATE as MAX_VENUES_PER_DATE_CONF,
    DROP_EVENTS_RETENTION_DAYS,
    METRICS_RETENTION_DAYS,
    USER_BEHAVIOR_EVENTS_RETENTION_DAYS,
    VENUES_RETENTION_DAYS,
)
from app.core.discovery_config import (
    DISCOVERY_BASELINE_CALIBRATION_POLLS,
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
from app.models.user_behavior_event import UserBehaviorEvent
from app.models.user_notification import UserNotification
from app.models.venue import Venue
from app.models.venue_rolling_metrics import VenueRollingMetrics
from app.services.discovery.drop_reads import latest_drop_row_per_pair, successful_poll_count_by_bucket
from app.services.discovery.eligibility import qualified_for_home_feed, stronger_eligibility_evidence
from app.services.discovery.likely_open_scoring import score_likely_open_rank
from app.services.discovery.venue_profile import normalize_http_url, venue_profile_from_payload
from app.services.aggregation import aggregate_closed_events_into_metrics
from app.services.providers import get_provider

logger = logging.getLogger(__name__)

# In-memory only: closed-event data for aggregation (we never persist CLOSED rows to drop_events)
# session_id: when set, aggregate marks session as aggregated (idempotency).
ClosedEventData = namedtuple(
    "ClosedEventData",
    [
        "venue_id",
        "venue_name",
        "drop_duration_seconds",
        "slot_date",
        "bucket_id",
        "session_id",
        "closed_at",
        "neighborhood",
        "market",
        "time_bucket",
    ],
    defaults=(None, None, None, None, None),
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


def bucket_id(date_str: str, time_slot: str, market: str = "nyc") -> str:
    """Stable bucket key.  Format: {market}_{date_str}_{time_slot}  e.g. nyc_2026-02-12_15:00."""
    return f"{market}_{date_str}_{time_slot}"


def _parse_bucket_id(bid: str) -> tuple[str, str, str]:
    """
    Parse bucket_id into (market, date_str, time_slot).

    Handles both the new format  {market}_{date}_{time}  and the legacy
    format  {date}_{time}  (pre-045 rows without market prefix, assumed nyc).
    """
    parts = bid.split("_", 2)
    if len(parts) == 3:
        return parts[0], parts[1], parts[2]   # new:  "nyc", "2026-02-12", "15:00"
    if len(parts) == 2:
        return "nyc", parts[0], parts[1]       # old:  "nyc", "2026-02-12", "15:00"
    return "nyc", bid, ""


def slot_id(venue_id: str, actual_time: str, provider: str = "resy") -> str:
    """
    Stable slot key for fast diff: one id per provider + venue + actual time.
    Delegates to providers.types.slot_id for consistency with provider output.
    """
    from app.services.providers.types import slot_id as make_slot_id
    return make_slot_id(provider, venue_id or "", actual_time or "")


def all_bucket_ids(today: date) -> list[tuple[str, str, str, str]]:
    """
    Returns (bucket_id, date_str, time_slot, market) for the 14-day window
    across all active markets.  Markets are read from DISCOVERY_MARKETS env var
    (default: nyc only).
    """
    from app.core.market_config import get_active_markets
    markets = get_active_markets()
    out: list[tuple[str, str, str, str]] = []
    for market in markets:
        for offset in range(WINDOW_DAYS):
            day = today + timedelta(days=offset)
            date_str = day.isoformat()
            for ts in TIME_SLOTS:
                out.append((bucket_id(date_str, ts, market.slug), date_str, ts, market.slug))
    return out


def fetch_for_bucket(
    date_str: str,
    time_slot: str,
    party_sizes: list[int],
    provider: str = "resy",
    market: str = "nyc",
) -> list[dict]:
    """
    Fetch current availability for one bucket via the given provider.
    Returns one row per (venue, actual_time): { "slot_id", "venue_id", "venue_name", "payload" }.
    All providers (Resy, OpenTable, etc.) return the same normalized shape.
    """
    try:
        prov = get_provider(provider)
    except KeyError:
        logger.warning("Unknown provider %s, skipping bucket %s", provider, bucket_id(date_str, time_slot, market))
        return []
    bid = bucket_id(date_str, time_slot, market)
    try:
        results = prov.search_availability(date_str, time_slot, party_sizes, market=market)
    except TypeError:
        # Fallback for providers that don't accept market kwarg (e.g. OpenTable)
        results = prov.search_availability(date_str, time_slot, party_sizes)
    except Exception as e:
        logger.warning("Provider %s search failed bucket=%s: %s", provider, bid, e)
        return []
    rows = [r.to_row() for r in results]
    if not rows:
        logger.debug("Provider %s returned 0 slots for bucket=%s (date=%s time_slot=%s market=%s) — baseline will be 0", provider, bid, date_str, time_slot, market)
    return rows


def _parse_slot_ids_json(js: str | None) -> set[str]:
    if not js:
        return set()
    try:
        arr = json.loads(js)
        return set(str(x) for x in arr if x)
    except (TypeError, json.JSONDecodeError):
        return set()


def _venue_ids_from_rows(rows: list[dict]) -> list[str]:
    """Unique non-empty venue_id strings from poll rows (same fetch as baseline_slot_ids)."""
    s = {str(r.get("venue_id") or "").strip() for r in rows if str(r.get("venue_id") or "").strip()}
    return sorted(s)


def _parse_venue_ids_json(js: str | None) -> set[str]:
    if not js:
        return set()
    try:
        arr = json.loads(js)
        return {str(x).strip() for x in arr if x and str(x).strip()}
    except (TypeError, json.JSONDecodeError):
        return set()


def _drop_eligibility_evidence_for_poll(
    prior_count: int,
    baseline_count: int,
    successful_polls_before: int,
) -> str:
    """
    CHECK v1 values on drop_events.eligibility_evidence (see TARGET_SCHEMA_AND_INVARIANTS §4).
    prior_count = len(prev) before this poll; baseline_count = len(baseline JSON);
    successful_polls_before = discovery_buckets.successful_poll_count before incrementing for this poll.
    """
    if prior_count > 0:
        return "nonempty_prev_delta"
    if successful_polls_before > 0:
        return "empty_prev_delta"
    if baseline_count > 0:
        return "baseline_only"
    return "first_poll_bucket"


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
    market: str = "nyc",
) -> dict:
    """Build one SlotAvailability row dict (open state). Used by bootstrap and drops."""
    payload = r.get("payload") if r else {}
    slot_date_val, slot_time_val = _slot_date_time_from_payload(payload, date_str)
    neighborhood_val = price_range_val = None
    image_url_val = None
    if isinstance(payload, dict):
        loc = payload.get("location")
        nh = payload.get("neighborhood") or (loc.get("neighborhood") if isinstance(loc, dict) else None)
        if nh is not None:
            neighborhood_val = str(nh)[:128] or None
        pr = payload.get("price_range")
        if pr is not None:
            price_range_val = str(pr)[:32] or None
        img = payload.get("image_url")
        if isinstance(img, str) and img.strip():
            image_url_val = img.strip()[:512] or None
    return {
        "bucket_id": bid,
        "slot_id": sid,
        "state": "open",
        "opened_at": now,
        "last_seen_at": now,
        "venue_id": r.get("venue_id") if r else None,
        "venue_name": r.get("venue_name") if r else None,
        "payload_json": None,
        "run_id": run_id or str(uuid.uuid4()),
        "updated_at": now,
        "time_bucket": time_bucket_val,
        "slot_date": slot_date_val,
        "slot_time": slot_time_val,
        "provider": provider,
        "neighborhood": neighborhood_val,
        "price_range": price_range_val,
        "image_url": image_url_val,
        "market": market,
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
    market: str = "nyc",
) -> None:
    """Write all curr_set to SlotAvailability (open). Used when creating a new bucket or when baseline was None."""
    if not curr_set:
        return
    run_id = str(uuid.uuid4())
    time_bucket_val = _time_bucket_from_slot(time_slot)
    by_slot = {r["slot_id"]: r for r in rows}
    bootstrap_rows = [
        _build_slot_availability_row(bid, sid, by_slot.get(sid), date_str, now, time_bucket_val, provider, run_id, market=market)
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
                SlotAvailability.run_id: ins.excluded.run_id,
                SlotAvailability.updated_at: ins.excluded.updated_at,
                SlotAvailability.time_bucket: ins.excluded.time_bucket,
                SlotAvailability.slot_date: ins.excluded.slot_date,
                SlotAvailability.slot_time: ins.excluded.slot_time,
                SlotAvailability.provider: ins.excluded.provider,
                SlotAvailability.neighborhood: ins.excluded.neighborhood,
                SlotAvailability.price_range: ins.excluded.price_range,
                SlotAvailability.image_url: ins.excluded.image_url,
                SlotAvailability.closed_at: None,
            },
            where=text("slot_availability.updated_at < excluded.updated_at"),
        ))


def _upsert_venue(
    db: Session,
    venue_id: str | None,
    venue_name: str | None,
    *,
    payload: dict | None = None,
    market: str | None = None,
) -> None:
    """Upsert venue profile when we see a live slot (image, neighborhood, Resy link).
    Uses ON CONFLICT DO UPDATE so concurrent polls for different buckets can safely
    insert the same venue without raising venues_pkey UniqueViolation.
    """
    if not venue_id or not str(venue_id).strip():
        return
    vid = str(venue_id).strip()
    name = (venue_name or "").strip() or None
    img, nbhd, resy = venue_profile_from_payload(payload)
    mkt = str(market).strip()[:32] if market and str(market).strip() else None
    now = datetime.now(timezone.utc)
    stmt = pg_insert(Venue).values(
        venue_id=vid,
        venue_name=name,
        image_url=img,
        neighborhood=nbhd,
        resy_url=resy,
        market=mkt,
    )
    update_cols: dict = {"last_seen_at": now}
    if name:
        update_cols["venue_name"] = stmt.excluded.venue_name
    if img:
        update_cols["image_url"] = stmt.excluded.image_url
    if nbhd:
        update_cols["neighborhood"] = stmt.excluded.neighborhood
    if resy:
        update_cols["resy_url"] = stmt.excluded.resy_url
    if mkt:
        update_cols["market"] = stmt.excluded.market
    db.execute(stmt.on_conflict_do_update(index_elements=["venue_id"], set_=update_cols))


def run_baseline_for_bucket(
    db: Session, bid: str, date_str: str, time_slot: str, provider: str = "resy", market: str = "nyc"
) -> int:
    """
    Fetch current state for bucket and set baseline = prev = curr. Replaces any previous baseline.
    Does NOT write to slot_availability or availability_state (no state/metrics from baseline).
    Returns slot count.
    """
    rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=provider, market=market)
    slot_ids = [r["slot_id"] for r in rows]
    venue_js = json.dumps(_venue_ids_from_rows(rows))
    now = datetime.now(timezone.utc)
    row = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id == bid).first()
    js = json.dumps(sorted(slot_ids))
    if row:
        # Overwrite previous baseline and prev with new snapshot (previous one is replaced, not kept)
        row.baseline_slot_ids_json = js
        row.baseline_venue_ids_json = venue_js
        row.prev_slot_ids_json = js
        row.scanned_at = now
        row.successful_poll_count = (row.successful_poll_count or 0) + 1
        row.baseline_calibration_complete = True
        row.baseline_calibration_polls = DISCOVERY_BASELINE_CALIBRATION_POLLS
        if not row.market:
            row.market = market
    else:
        db.add(
            DiscoveryBucket(
                bucket_id=bid,
                date_str=date_str,
                time_slot=time_slot,
                market=market,
                baseline_slot_ids_json=js,
                baseline_venue_ids_json=venue_js,
                prev_slot_ids_json=js,
                scanned_at=now,
                successful_poll_count=1,
                baseline_calibration_complete=True,
                baseline_calibration_polls=DISCOVERY_BASELINE_CALIBRATION_POLLS,
            )
        )
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
    for i, (bid, date_str, time_slot, market) in enumerate(buckets, start=1):
        try:
            slot_count = run_baseline_for_bucket(db, bid, date_str, time_slot, market=market)
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
    db: Session, bid: str, date_str: str, time_slot: str, provider: str = "resy", market: str = "nyc"
) -> tuple[int, int, dict]:
    """
    Poll one bucket: fetch curr (network, outside tx), then in a short write tx: lease bucket,
    compute diff, apply projection + sessions, commit. Apply only if our run is newer (last-writer-wins).

    Until baseline calibration completes, we merge unions of slot_id and venue_id across
    DISCOVERY_BASELINE_CALIBRATION_POLLS successful scans (no DropEvents / slot_availability writes).
    That locks a stronger “what had inventory” snapshot so drops mean “new vs that union,”
    not a single flaky poll.

    Returns (drops_emitted, current_slot_count, invariant_stats).
    """
    # Network I/O first (no DB transaction)
    rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=provider, market=market)
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
        db.add(
            DiscoveryBucket(
                bucket_id=bid,
                date_str=date_str,
                time_slot=time_slot,
                market=market,
                baseline_calibration_complete=False,
                baseline_calibration_polls=0,
            )
        )
        db.commit()
        bucket_row = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id == bid).first()
        if not bucket_row:
            logger.error("Bucket %s: failed to persist discovery_buckets row", bid)
            db.rollback()
            return 0, len(curr_set), {"skipped": True, "reason": "no_bucket_row"}

    if bucket_row.baseline_calibration_complete and bucket_row.baseline_slot_ids_json is None:
        bucket_row.baseline_calibration_complete = False
        bucket_row.baseline_calibration_polls = 0
        logger.warning(
            "Bucket %s: inconsistent state (calibration complete but no baseline); resetting calibration",
            bid,
        )
        if not curr_set:
            db.commit()
            return 0, 0, {
                "B": 0,
                "P": 0,
                "C": 0,
                "baseline_ready": False,
                "emitted": 0,
                "reset_inconsistent": True,
            }

    if not bucket_row.baseline_calibration_complete:
        if not curr_set:
            if bucket_row.baseline_slot_ids_json is None:
                logger.warning(
                    "Bucket %s: skipping baseline init — Resy returned 0 slots for date=%s "
                    "time_slot=%s. Will retry next poll.",
                    bid,
                    date_str,
                    time_slot,
                )
            else:
                logger.warning(
                    "Bucket %s: calibration poll skipped — empty response (date=%s time_slot=%s). Will retry.",
                    bid,
                    date_str,
                    time_slot,
                )
            db.rollback()
            return 0, 0, {
                "B": 0,
                "P": 0,
                "C": 0,
                "baseline_ready": False,
                "emitted": 0,
                "calibration": True,
                "skipped_empty": True,
            }

        slot_union = _parse_slot_ids_json(bucket_row.baseline_slot_ids_json) | curr_set
        venue_union = _parse_venue_ids_json(bucket_row.baseline_venue_ids_json) | set(_venue_ids_from_rows(rows))
        cal_before = int(bucket_row.baseline_calibration_polls or 0)
        bucket_row.baseline_slot_ids_json = json.dumps(sorted(slot_union))
        bucket_row.baseline_venue_ids_json = json.dumps(sorted(venue_union))
        bucket_row.prev_slot_ids_json = json.dumps(sorted(curr_set))
        bucket_row.baseline_calibration_polls = cal_before + 1
        bucket_row.scanned_at = now
        bucket_row.successful_poll_count = (bucket_row.successful_poll_count or 0) + 1
        n_cal = bucket_row.baseline_calibration_polls
        if n_cal >= DISCOVERY_BASELINE_CALIBRATION_POLLS:
            bucket_row.baseline_calibration_complete = True
            logger.info(
                "Bucket %s: baseline calibration complete after %s polls (|S|=%s |V|=%s)",
                bid,
                n_cal,
                len(slot_union),
                len(venue_union),
            )
        else:
            logger.info(
                "Bucket %s: baseline calibration poll %s/%s (|S|=%s)",
                bid,
                n_cal,
                DISCOVERY_BASELINE_CALIBRATION_POLLS,
                len(slot_union),
            )
        db.commit()
        return 0, len(curr_set), {
            "B": len(slot_union),
            "P": len(curr_set),
            "C": len(curr_set),
            "baseline_ready": bucket_row.baseline_calibration_complete,
            "emitted": 0,
            "baseline_echo": 0,
            "prev_echo": 0,
            "calibration": True,
            "calibration_poll": n_cal,
        }

    baseline_js = bucket_row.baseline_slot_ids_json
    if baseline_js is None:
        logger.error("Bucket %s: baseline missing after calibration; skipping poll", bid)
        db.rollback()
        return 0, len(curr_set), {"error": "no_baseline_after_calibration"}

    baseline_set = _parse_slot_ids_json(baseline_js)
    prev_set = _parse_slot_ids_json(bucket_row.prev_slot_ids_json)
    B = len(baseline_set)
    P, C = len(prev_set), len(curr_set)
    polls_before = int(bucket_row.successful_poll_count or 0)
    drop_evidence = _drop_eligibility_evidence_for_poll(P, B, polls_before)
    prior_prev_slot_count = P

    # prev: dedupe “already seen this poll line” / close detection. Not the product definition of “drop”.
    added = curr_set - prev_set
    # Slot-level: new lines vs baseline snapshot (hashes). Still allows “new time” at a venue
    # that already had other times at baseline — venue filter below removes those.
    drops = added - baseline_set

    by_slot = {r["slot_id"]: r for r in rows}
    # Product gate: only venues with **no** times at all in baseline qualify. If baseline
    # already showed any slot for this venue, we ignore further “new times” (and hash drift).
    baseline_venues = _parse_venue_ids_json(bucket_row.baseline_venue_ids_json)
    inferred_venues = {
        str(r.get("venue_id") or "").strip()
        for r in rows
        if r.get("slot_id") in baseline_set and str(r.get("venue_id") or "").strip()
    }
    if inferred_venues:
        merged_v = baseline_venues | inferred_venues
        if merged_v != baseline_venues or bucket_row.baseline_venue_ids_json is None:
            bucket_row.baseline_venue_ids_json = json.dumps(sorted(merged_v))
            baseline_venues = merged_v
    if baseline_venues:
        before_drop = len(drops)
        drops = {
            sid
            for sid in drops
            if str((by_slot.get(sid) or {}).get("venue_id") or "").strip() not in baseline_venues
        }
        n_venue_fp = before_drop - len(drops)
        if n_venue_fp:
            logger.info(
                "Bucket %s: excluded %s slot candidate(s) — venue had ≥1 time in baseline (not a full-booking reopen)",
                bid,
                n_venue_fp,
            )

    run_id = str(uuid.uuid4())
    time_bucket_val = _time_bucket_from_slot(time_slot)
    # TTL dedupe: don't create DropEvent if we already notified for this (bucket_id, slot_id) recently
    cutoff = now - timedelta(minutes=NOTIFIED_DEDUPE_MINUTES)
    recently_notified = {
        row[0]
        for row in db.query(DropEvent.slot_id).filter(
            DropEvent.bucket_id == bid,
            DropEvent.user_facing_opened_at >= cutoff,
        ).distinct().all()
    }
    # One live DropEvent per (bucket, slot): TTL alone re-allows emits every NOTIFIED_DEDUPE_MINUTES when
    # the slot keeps reappearing in `added` without a clean close (Resy flicker / prev gaps), stacking rows.
    dup_open: set[str] = set()
    if drops:
        dup_open = {
            row[0]
            for row in db.query(DropEvent.slot_id)
            .join(
                SlotAvailability,
                and_(
                    SlotAvailability.bucket_id == DropEvent.bucket_id,
                    SlotAvailability.slot_id == DropEvent.slot_id,
                    SlotAvailability.state == "open",
                ),
            )
            .filter(DropEvent.bucket_id == bid, DropEvent.slot_id.in_(list(drops)))
            .distinct()
            .all()
        }
    # Emit DropEvent for **every** newly added slot, not only when the venue had zero slots last poll.
    # `get_just_opened_from_buckets` joins DropEvent × open SlotAvailability; the old venue-zero gate
    # left most real openings without events (venue already had another time) → empty `just_opened` while
    # `just_missed` still populated when those slots closed. TTL + dup_open keep noise bounded.
    drops_to_emit = set(drops) - recently_notified - dup_open

    # --- Projection: all added go to SlotAvailability; drops_to_emit get a DropEvent (new slot lines this poll) ---
    slot_rows = [
        _build_slot_availability_row(bid, sid, by_slot.get(sid), date_str, now, time_bucket_val, provider, run_id, market=market)
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
        # Store full venue card so feed has image_url, resy_url, etc.
        payload_to_store = dict(payload) if isinstance(payload, dict) else {}
        drop_rows.append({
            "bucket_id": bid,
            "slot_id": sid,
            "opened_at": now,
            "user_facing_opened_at": now,
            "venue_id": r.get("venue_id") if r else None,
            "venue_name": r.get("venue_name") if r else None,
            "payload_json": json.dumps(payload_to_store) if payload_to_store else None,
            "dedupe_key": f"{bid}|{sid}|{now.strftime('%Y-%m-%dT%H:%M')}",
            "time_bucket": time_bucket_val,
            "slot_date": slot_date_val,
            "slot_time": slot_time_val,
            "provider": provider,
            "neighborhood": neighborhood_val,
            "price_range": price_range_val,
            "market": market,
            "eligibility_evidence": drop_evidence,
            "prior_snapshot_included_slot": False,
            "prior_prev_slot_count": prior_prev_slot_count,
        })

    for sid in drops:
        r = by_slot.get(sid)
        if not r:
            continue
        pl = r.get("payload")
        pl_dict = pl if isinstance(pl, dict) else None
        _upsert_venue(db, r.get("venue_id"), r.get("venue_name"), payload=pl_dict, market=market)

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
                SlotAvailability.run_id: ins.excluded.run_id,
                SlotAvailability.updated_at: ins.excluded.updated_at,
                SlotAvailability.time_bucket: ins.excluded.time_bucket,
                SlotAvailability.slot_date: ins.excluded.slot_date,
                SlotAvailability.slot_time: ins.excluded.slot_time,
                SlotAvailability.provider: ins.excluded.provider,
                SlotAvailability.neighborhood: ins.excluded.neighborhood,
                SlotAvailability.price_range: ins.excluded.price_range,
                SlotAvailability.image_url: ins.excluded.image_url,
                SlotAvailability.closed_at: None,
                SlotAvailability.market: ins.excluded.market,
            },
            where=text("slot_availability.updated_at < excluded.updated_at"),
        ))
    # DEFENSIVE: reject any rows that somehow have null/unknown evidence before inserting.
    # Every legitimate drop must have a known evidence type from _drop_eligibility_evidence_for_poll.
    suspicious = [r for r in drop_rows if r.get("eligibility_evidence") in (None, "unknown")]
    if suspicious:
        logger.error(
            "BUG: %d drop_rows with null/unknown evidence in bucket %s (P=%s B=%s polls=%s). "
            "Dropping them to avoid polluting the feed.",
            len(suspicious), bid, P, B, polls_before,
        )
        drop_rows = [r for r in drop_rows if r.get("eligibility_evidence") not in (None, "unknown")]

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

    if drop_rows:
        _bump_venue_last_drop_opened_at(db, drop_rows)

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
            "market": market,
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
                AvailabilityState.market: stmt.excluded.market,
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
        ).delete(synchronize_session=False)
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
                    closed_at=now,
                    neighborhood=row.neighborhood,
                    market=row.market or market,
                    time_bucket=row.time_bucket,
                ))

    bucket_row.prev_slot_ids_json = json.dumps(sorted(curr_set))
    bucket_row.scanned_at = now
    bucket_row.successful_poll_count = polls_before + 1

    # Remove drop_events for closed slots (open-drop rows are not history; keeps table bounded).
    # Do not require push_sent_at — most rows never get a push (eligibility / unwatched venues).
    if closed_slot_ids:
        n_dropped = (
            db.query(DropEvent)
            .filter(
                DropEvent.bucket_id == bid,
                DropEvent.slot_id.in_(closed_slot_ids),
            )
            .delete(synchronize_session=False)
        )
        if n_dropped:
            logger.debug("Pruned %s drop_events (closed slots) for bucket %s", n_dropped, bid)

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
    """Ensure all buckets exist for all active markets (create with empty baseline/prev if missing)."""
    buckets = list(all_bucket_ids(today))
    existing_rows = (
        db.query(DiscoveryBucket.bucket_id)
        .filter(DiscoveryBucket.bucket_id.in_([b[0] for b in buckets]))
        .all()
    )
    existing_ids = {r[0] for r in existing_rows}
    to_add = [
        DiscoveryBucket(bucket_id=bid, date_str=date_str, time_slot=time_slot, market=market)
        for bid, date_str, time_slot, market in buckets
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


def _bump_venue_last_drop_opened_at(db: Session, drop_rows: list[dict]) -> None:
    """Set venues.last_drop_opened_at = GREATEST(existing, new) for each venue_id in emitted drops."""
    by_vid: dict[str, datetime] = {}
    for row in drop_rows:
        vid = row.get("venue_id")
        ts = row.get("user_facing_opened_at")
        if not vid or ts is None:
            continue
        if getattr(ts, "tzinfo", None) is None:
            ts = ts.replace(tzinfo=timezone.utc)
        cur = by_vid.get(vid)
        if cur is None or ts > cur:
            by_vid[vid] = ts
    if not by_vid:
        return
    for vid, ts in by_vid.items():
        db.execute(
            text(
                """
                UPDATE venues
                SET last_drop_opened_at = GREATEST(
                    COALESCE(last_drop_opened_at, TIMESTAMP WITH TIME ZONE '-infinity'),
                    CAST(:ts AS TIMESTAMP WITH TIME ZONE)
                )
                WHERE venue_id = :vid
                """
            ),
            {"vid": vid, "ts": ts},
        )


def prune_drop_events_without_open_slot(
    db: Session, batch_size: int = 25_000, max_batches: int | None = None
) -> int:
    """
    Delete drop_events with no open slot_availability row for the same (bucket_id, slot_id).

    Invariant: a DropEvent is only meaningful while that slot is still in the live projection. Rows left
    behind (crashes, old code, failed commits) grow without bound; this reclaims them in batches.
    """
    total = 0
    batches = 0
    while True:
        batches += 1
        result = db.execute(
            text(
                """
                DELETE FROM drop_events
                WHERE id IN (
                    SELECT de.id
                    FROM drop_events de
                    WHERE NOT EXISTS (
                        SELECT 1 FROM slot_availability sa
                        WHERE sa.bucket_id = de.bucket_id
                          AND sa.slot_id = de.slot_id
                          AND sa.state = 'open'
                    )
                    LIMIT :lim
                )
                """
            ),
            {"lim": batch_size},
        )
        n = int(result.rowcount or 0)
        total += n
        db.commit()
        if n < batch_size:
            break
        if max_batches is not None and batches >= max_batches:
            break
    if total:
        logger.info("prune_drop_events_without_open_slot removed %s orphan drop_event row(s)", total)
    return total


def prune_extra_drop_events_per_open_slot(
    db: Session, batch_size: int = 10_000, max_batches: int | None = None
) -> int:
    """
    For (bucket_id, slot_id) pairs that still have an **open** slot_availability row, keep only the
    latest drop_event (by user_facing_opened_at, then id) and delete older duplicates.

    Safe for feed/push: one canonical row per live slot; eligibility/payload should match the latest open.
    """
    total = 0
    batches = 0
    while True:
        batches += 1
        result = db.execute(
            text(
                """
                WITH ranked AS (
                    SELECT de.id,
                           ROW_NUMBER() OVER (
                               PARTITION BY de.bucket_id, de.slot_id
                               ORDER BY de.user_facing_opened_at DESC, de.id DESC
                           ) AS rn
                    FROM drop_events de
                    WHERE EXISTS (
                        SELECT 1 FROM slot_availability sa
                        WHERE sa.bucket_id = de.bucket_id
                          AND sa.slot_id = de.slot_id
                          AND sa.state = 'open'
                    )
                ),
                doomed AS (SELECT id FROM ranked WHERE rn > 1 LIMIT :lim)
                DELETE FROM drop_events WHERE id IN (SELECT id FROM doomed)
                """
            ),
            {"lim": batch_size},
        )
        n = int(result.rowcount or 0)
        total += n
        db.commit()
        if n < batch_size:
            break
        if max_batches is not None and batches >= max_batches:
            break
    if total:
        logger.info("prune_extra_drop_events_per_open_slot removed %s duplicate row(s)", total)
    return total


def delete_closed_drop_events(db: Session, batch_size: int = 50_000) -> int:
    """
    No-op: we no longer persist CLOSED rows to drop_events. Kept for API compatibility (daily job).
    """
    return 0


def prune_old_drop_events(db: Session, today: date) -> int:
    """
    Keep drop_events bounded: (1) remove rows for reservation slot_date before calendar today;
    (2) remove rows older than DROP_EVENTS_RETENTION_DAYS by user_facing_opened_at (all rows —
    not only pushed; otherwise never-pushed events grow without bound).

    venue_metrics.new_drop_count is updated with monotonic max from aggregate_open_drops_into_metrics,
    so shrinking live row counts does not decrease stored counts.
    """
    today_str = today.isoformat()
    # Rows with slot_date set (all rows written after migration 042)
    n_bucket = (
        db.query(DropEvent)
        .filter(DropEvent.slot_date < today_str, DropEvent.slot_date.isnot(None))
        .delete(synchronize_session=False)
    )
    # Time-based: any stale open-drop row (push is optional; most rows never get push_sent_at)
    cutoff_time = datetime.now(timezone.utc) - timedelta(days=DROP_EVENTS_RETENTION_DAYS)
    n_time = (
        db.query(DropEvent)
        .filter(DropEvent.user_facing_opened_at < cutoff_time)
        .delete(synchronize_session=False)
    )
    db.commit()
    n = n_bucket + n_time
    if n:
        logger.info(
            "Pruned %s drop_events (slot_date<%s: %s, user_facing_opened_at older than %s days: %s)",
            n, today_str, n_bucket, DROP_EVENTS_RETENTION_DAYS, n_time,
        )
    return n


def prune_old_slot_availability(db: Session, today: date) -> int:
    """Remove projection rows for slot dates before today (retention). Uses slot_date column."""
    today_str = today.isoformat()
    n = (
        db.query(SlotAvailability)
        .filter(SlotAvailability.slot_date < today_str, SlotAvailability.slot_date.isnot(None))
        .delete(synchronize_session=False)
    )
    db.commit()
    if n:
        logger.info("Pruned %s slot_availability (slot_date < %s)", n, today_str)
    return n


def prune_old_sessions(db: Session, today: date) -> int:
    """No-op: we use availability_state now. Kept for API compatibility (daily job)."""
    return 0


def prune_old_availability_state(db: Session, today: date) -> int:
    """Remove availability_state rows for slot dates before today. Uses slot_date column."""
    today_str = today.isoformat()
    n = (
        db.query(AvailabilityState)
        .filter(AvailabilityState.slot_date < today_str, AvailabilityState.slot_date.isnot(None))
        .delete(synchronize_session=False)
    )
    db.commit()
    if n:
        logger.info("Pruned %s availability_state (slot_date < %s)", n, today_str)
    return n


def prune_old_notifications(db: Session) -> int:
    """Remove user_notifications older than NOTIFICATIONS_RETENTION_DAYS (scheduled daily, not in hot path)."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=NOTIFICATIONS_RETENTION_DAYS)
    n = db.query(UserNotification).filter(UserNotification.created_at < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s user_notifications (created_at > %s days)", n, NOTIFICATIONS_RETENTION_DAYS)
    return n


def prune_old_user_behavior_events(db: Session) -> int:
    """Remove client behavior events older than USER_BEHAVIOR_EVENTS_RETENTION_DAYS."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=USER_BEHAVIOR_EVENTS_RETENTION_DAYS)
    n = db.query(UserBehaviorEvent).filter(UserBehaviorEvent.occurred_at < cutoff).delete(synchronize_session=False)
    db.commit()
    if n:
        logger.info("Pruned %s user_behavior_events (occurred_at older than %s days)", n, USER_BEHAVIOR_EVENTS_RETENTION_DAYS)
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


LIKELY_TO_OPEN_LIMIT = 25
# Pre-filter pool before composite sort (avoids loading unbounded rows per market).
LIKELY_TO_OPEN_CANDIDATE_POOL = 400


def _hours_since_utc(last_open: datetime | None, now: datetime) -> float | None:
    if last_open is None:
        return None
    ts = last_open
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return max(0.0, (now - ts).total_seconds() / 3600.0)


def _max_opened_at_by_venue(db: Session, venue_ids: list[str]) -> dict[str, datetime]:
    """Latest drop_event.user_facing_opened_at per venue (all time in DB — recency is capped in scoring)."""
    from app.models.drop_event import DropEvent

    if not venue_ids:
        return {}
    out: dict[str, datetime] = {}
    chunk = 400
    for i in range(0, len(venue_ids), chunk):
        part = venue_ids[i : i + chunk]
        q = (
            db.query(DropEvent.venue_id, func.max(DropEvent.user_facing_opened_at))
            .filter(DropEvent.venue_id.in_(part))
            .group_by(DropEvent.venue_id)
        )
        for vid, ts in q.all():
            if vid is not None and ts is not None:
                out[str(vid)] = ts
    return out


def get_likely_to_open_venues(db: Session, today: date, limit: int = LIKELY_TO_OPEN_LIMIT) -> list[dict]:
    """
    Venues with no open slots *now* that rank highest for **forecast** new openings soon.
    Uses rolling metrics + **last drop time** (recency): recently released but empty now → top picks.
    Client copy/score: `likely_open_scoring.enrich_likely_open_item`.
    Returns 'name' (not just 'venue_name') so iOS clients can decode without remapping.
    """
    from app.models.drop_event import DropEvent

    bucket_ids = [bid for bid, _d, _t, _m in all_bucket_ids(today)]
    open_venue_ids = set(
        r[0]
        for r in db.query(SlotAvailability.venue_id)
        .filter(
            SlotAvailability.bucket_id.in_(bucket_ids),
            SlotAvailability.state == "open",
            SlotAvailability.venue_id.isnot(None),
        )
        .distinct()
        .all()
    )
    latest = db.query(func.max(VenueRollingMetrics.as_of_date)).scalar()
    if not latest:
        return []
    base_q = db.query(VenueRollingMetrics).filter(
        VenueRollingMetrics.as_of_date == latest,
        VenueRollingMetrics.venue_id.notin_(open_venue_ids) if open_venue_ids else True,
    )
    rows = base_q.all()
    if not rows:
        return []

    now_utc = datetime.now(timezone.utc)
    vids = list({str(r.venue_id) for r in rows if r.venue_id})
    last_open_by_vid = _max_opened_at_by_venue(db, vids)

    def _hours_for_row(r: VenueRollingMetrics) -> float | None:
        if not r.venue_id:
            return None
        return _hours_since_utc(last_open_by_vid.get(str(r.venue_id)), now_utc)

    # Cap candidate count using the same forecast score (recency-aware).
    if len(rows) > LIKELY_TO_OPEN_CANDIDATE_POOL:
        rows = sorted(
            rows,
            key=lambda r: score_likely_open_rank(
                r.availability_rate_14d,
                r.days_with_drops,
                r.drop_frequency_per_day,
                r.trend_pct,
                r.total_last_7d,
                _hours_for_row(r),
            ),
            reverse=True,
        )[:LIKELY_TO_OPEN_CANDIDATE_POOL]
    rows = sorted(
        rows,
        key=lambda r: score_likely_open_rank(
            r.availability_rate_14d,
            r.days_with_drops,
            r.drop_frequency_per_day,
            r.trend_pct,
            r.total_last_7d,
            _hours_for_row(r),
        ),
        reverse=True,
    )[:limit]

    import json as _json

    # Best-effort enrichment: recent DropEvents + persisted `venues` row (image/neighborhood cache)
    venue_ids = [r.venue_id for r in rows if r.venue_id]
    neighborhood_by_vid: dict[str, str] = {}
    image_url_by_vid: dict[str, str] = {}
    modal_hour_by_vid: dict[str, int] = {}
    try:
        metrics_tz = ZoneInfo(DISCOVERY_DATE_TIMEZONE)
    except Exception:
        metrics_tz = timezone.utc
    if venue_ids:
        try:
            recent_events = (
                db.query(
                    DropEvent.venue_id,
                    DropEvent.neighborhood,
                    DropEvent.payload_json,
                    DropEvent.user_facing_opened_at,
                )
                .filter(
                    DropEvent.venue_id.in_(venue_ids),
                )
                .order_by(DropEvent.user_facing_opened_at.desc())
                .limit(len(venue_ids) * 8)
                .all()
            )
            # Collect hours per venue for modal computation (local clock = discovery TZ, not UTC)
            hours_by_vid: dict[str, list[int]] = {}
            for vid, nbhd, payload_str, opened_at in recent_events:
                if not vid:
                    continue
                vks = str(vid)
                if nbhd and vks not in neighborhood_by_vid:
                    neighborhood_by_vid[vks] = nbhd
                if payload_str and vks not in image_url_by_vid:
                    try:
                        payload = _json.loads(payload_str)
                        img = (
                            payload.get("image_url")
                            or payload.get("images", {}).get("thumbnail")
                            or payload.get("images", {}).get("small")
                        )
                        if img:
                            nu = normalize_http_url(str(img).strip())
                            if nu:
                                image_url_by_vid[vks] = nu
                    except (ValueError, AttributeError, TypeError):
                        pass
                if opened_at is not None:
                    ot = opened_at
                    if ot.tzinfo is None:
                        ot = ot.replace(tzinfo=timezone.utc)
                    hours_by_vid.setdefault(vks, []).append(ot.astimezone(metrics_tz).hour)
            # Modal hour = most common local hour of observed drops
            for vid, hours in hours_by_vid.items():
                from collections import Counter
                counts = Counter(hours)
                modal_hour_by_vid[vid] = counts.most_common(1)[0][0]
        except Exception:
            pass

    # Fallback: slot_availability.image_url from live polls (DropEvent payload often missing for older rows).
    if venue_ids:
        try:
            sa_rows = (
                db.query(SlotAvailability.venue_id, SlotAvailability.image_url, SlotAvailability.last_seen_at)
                .filter(
                    SlotAvailability.venue_id.in_(venue_ids),
                    SlotAvailability.image_url.isnot(None),
                )
                .order_by(SlotAvailability.last_seen_at.desc().nullslast())
                .limit(500)
                .all()
            )
            for vid, iurl, _ in sa_rows:
                if not vid or not iurl or not str(iurl).strip():
                    continue
                vks = str(vid)
                if vks in image_url_by_vid:
                    continue
                nu = normalize_http_url(str(iurl).strip())
                if nu:
                    image_url_by_vid[vks] = nu
        except Exception:
            pass

    venue_profile_by_id: dict[str, Venue] = {}
    if venue_ids:
        for vr in db.query(Venue).filter(Venue.venue_id.in_(venue_ids)).all():
            venue_profile_by_id[str(vr.venue_id)] = vr

    out: list[dict] = []
    for r in rows:
        vk = str(r.venue_id) if r.venue_id else ""
        vp = venue_profile_by_id.get(vk)
        nb = neighborhood_by_vid.get(vk) or (vp.neighborhood if vp and vp.neighborhood else None)
        im = image_url_by_vid.get(vk) or (vp.image_url if vp and vp.image_url else None)
        im = normalize_http_url(im) if im else None
        out.append(
            {
                "venue_id": r.venue_id,
                "venue_name": r.venue_name or "",
                "name": r.venue_name or "",  # iOS CodingKey expects "name"
                "neighborhood": nb or "",
                "image_url": im or "",
                "availability_rate_14d": r.availability_rate_14d,
                "days_with_drops": r.days_with_drops,
                "rarity_score": r.rarity_score,
                "trend_pct": r.trend_pct,
                "drop_frequency_per_day": r.drop_frequency_per_day,
                "total_last_7d": r.total_last_7d,
                "total_prev_7d": r.total_prev_7d,
                "total_new_drops": r.total_new_drops,
                # Internal until enrich_likely_open_item strips them
                "hours_since_last_drop": _hours_for_row(r),
                "modal_drop_hour": modal_hour_by_vid.get(vk),
            }
        )
    return out


def _poll_one_bucket(bid: str, date_str: str, time_slot: str, market: str = "nyc") -> tuple[int, dict, str | None]:
    """
    Poll a single bucket in its own DB session (for use in thread pool).
    Returns (drops_emitted, stats, error_bid or None).
    """
    db = SessionLocal()
    try:
        n_drops, _, stats = run_poll_for_bucket(db, bid, date_str, time_slot, market=market)
        return (n_drops, stats, None)
    except Exception as e:
        logger.exception("Poll bucket %s failed: %s", bid, e)
        return (0, {}, bid)
    finally:
        db.close()


def run_poll_all_buckets(db: Session, today: date) -> dict:
    """
    Run poll for all active-market buckets in parallel so the whole run finishes in ~1–2 min.
    Each bucket is re-scanned after cooldown; tick every 3s dispatches ready buckets. Failed buckets are retried once (sequential).
    Returns { "buckets_polled", "drops_emitted", "last_scan_at", "errors", "invariants" }.
    """
    ensure_buckets(db, today)
    buckets = list(all_bucket_ids(today))
    drops_emitted = 0
    buckets_baseline_ready = 0
    errors: list[tuple[str, str, str, str]] = []

    max_workers = min(len(buckets), DISCOVERY_MAX_CONCURRENT_BUCKETS)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_bucket = {
            executor.submit(_poll_one_bucket, bid, date_str, time_slot, market): (bid, date_str, time_slot, market)
            for bid, date_str, time_slot, market in buckets
        }
        for future in as_completed(future_to_bucket):
            bid, date_str, time_slot, market = future_to_bucket[future]
            try:
                n_drops, stats, err_bid = future.result()
                if err_bid:
                    errors.append((bid, date_str, time_slot, market))
                    continue
                drops_emitted += n_drops
                if stats.get("baseline_ready"):
                    buckets_baseline_ready += 1
            except Exception as e:
                logger.exception("Future for bucket %s raised: %s", bid, e)
                errors.append((bid, date_str, time_slot, market))

    # Retry failed buckets once (sequential, same process)
    retried: list[str] = []
    for bid, date_str, time_slot, market in list(errors):
        logger.warning("Retrying bucket %s", bid)
        n_drops, stats, err_bid = _poll_one_bucket(bid, date_str, time_slot, market)
        if err_bid:
            continue
        retried.append(bid)
        drops_emitted += n_drops
        if stats.get("baseline_ready"):
            buckets_baseline_ready += 1
    errors = [(b, d, t, m) for b, d, t, m in errors if b not in retried]
    error_ids = [b for b, _, _, _ in errors]

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
    all_bids_list = all_bucket_ids(today)
    bucket_ids = [bid for bid, _d, _t, _m in all_bids_list]
    rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
    by_bucket = {r.bucket_id: r for r in rows}
    out = []
    for bid, date_str, time_slot, market in all_bids_list:
        row = by_bucket.get(bid)
        last_scan = row.scanned_at if row and row.scanned_at else None
        out.append({
            "bucket_id": bid,
            "date_str": date_str,
            "time_slot": time_slot,
            "market": market,
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
    all_bids_list = all_bucket_ids(today)
    bucket_ids = [bid for bid, _d, _t, _m in all_bids_list]
    rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
    by_bucket = {r.bucket_id: r for r in rows}
    buckets = []
    for bid, date_str, time_slot, market in all_bids_list:
        row = by_bucket.get(bid)
        slot_ids = _parse_slot_ids_json(row.baseline_slot_ids_json) if row else set()
        buckets.append({
            "bucket_id": bid,
            "date_str": date_str,
            "time_slot": time_slot,
            "market": market,
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


def _bucket_time_slot(bucket_id_val: str) -> str:
    """Extract time_slot from bucket_id. Handles both new (market_date_time) and old (date_time) formats."""
    _, _, ts = _parse_bucket_id(bucket_id_val)
    return ts


def _bucket_date_str(bucket_id_val: str) -> str:
    """Extract date_str from bucket_id. Handles both new and old formats."""
    _, date_str, _ = _parse_bucket_id(bucket_id_val)
    return date_str


def _bucket_market(bucket_id_val: str) -> str:
    """Extract market from bucket_id. Handles both new and old formats."""
    market, _, _ = _parse_bucket_id(bucket_id_val)
    return market


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
    Just opened: only venues that had ZERO slots in the previous poll and now have some (true drops).
    Uses DropEvent so we only show "fully booked → spots opened up", not venues that already had slots and gained more.
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
    # Only slots that are true drops (non-unknown evidence = baseline-subtraction verified)
    drop_pairs = [
        (r.bucket_id, r.slot_id)
        for r in db.query(DropEvent.bucket_id, DropEvent.slot_id)
        .filter(
            DropEvent.user_facing_opened_at >= cutoff,
            DropEvent.eligibility_evidence != "unknown",
        )
        .distinct()
        .limit(limit_events)
        .all()
    ]
    if not drop_pairs:
        return []
    drop_meta = latest_drop_row_per_pair(db, list(drop_pairs), cutoff)
    poll_by_bucket = successful_poll_count_by_bucket(db, list({p[0] for p in drop_pairs}))
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
        date_str = _bucket_date_str(r.bucket_id)
        if date_filter is not None and date_str not in date_filter:
            continue
        if date_str not in by_date:
            by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
            by_venue[date_str] = {}
        payload = json.loads(r.payload_json) if r.payload_json else {}
        if not isinstance(payload, dict):
            payload = {}
        # Enrich from row when payload is empty (we no longer store payload_json)
        if not payload.get("venue_id") and r.venue_id:
            payload["venue_id"] = r.venue_id
        if not payload.get("name") and r.venue_name:
            payload["name"] = r.venue_name
        if getattr(r, "image_url", None) and not payload.get("image_url"):
            payload["image_url"] = r.image_url
        r_market = getattr(r, "market", None) or _bucket_market(r.bucket_id)
        if not payload.get("market"):
            payload["market"] = r_market
        venue_key = str(payload.get("venue_id") or payload.get("name") or "").strip() or "unknown"
        if not _venue_matches_party_sizes(payload, party_sizes):
            continue
        if venue_key not in by_venue[date_str]:
            by_venue[date_str][venue_key] = []
        pair_k = (r.bucket_id, r.slot_id)
        dm = drop_meta.get(pair_k)
        b_polls = poll_by_bucket.get(r.bucket_id)
        if dm:
            ufa = dm["user_facing_opened_at"]
            payload["user_facing_opened_at"] = ufa.isoformat() if ufa else None
            payload["eligibility_evidence"] = dm["eligibility_evidence"]
            payload["prior_prev_slot_count"] = dm["prior_prev_slot_count"]
            payload["prior_snapshot_included_slot"] = dm["prior_snapshot_included_slot"]
            payload["detected_at"] = ufa.isoformat() if ufa else (
                r.opened_at.isoformat() if r.opened_at else payload.get("detected_at")
            )
        else:
            payload["eligibility_evidence"] = "unknown"
            payload["prior_prev_slot_count"] = 0
            payload["prior_snapshot_included_slot"] = False
            payload["detected_at"] = r.opened_at.isoformat() if r.opened_at else payload.get("detected_at")
        payload["bucket_successful_poll_count"] = b_polls
        payload["_snag_feed_qualified"] = qualified_for_home_feed(
            payload.get("eligibility_evidence"),
            b_polls,
        )
        payload["name"] = r.venue_name or payload.get("name")
        by_venue[date_str][venue_key].append((r, payload))

    # Build one venue per (date_str, venue_key) with availability_times = all slot times from all rows
    for date_str in by_venue:
        for venue_key, row_payloads in by_venue[date_str].items():
            _, first_payload = row_payloads[0]
            merged_ev = first_payload.get("eligibility_evidence")
            any_qualified = bool(first_payload.get("_snag_feed_qualified"))
            for _r, pl in row_payloads[1:]:
                merged_ev = stronger_eligibility_evidence(merged_ev, pl.get("eligibility_evidence"))
                any_qualified = any_qualified or bool(pl.get("_snag_feed_qualified"))
            first_payload["eligibility_evidence"] = merged_ev
            first_payload["_snag_feed_qualified"] = any_qualified
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
    Still open: slots that are currently open but not in "just opened" (no recent DropEvent for this slot).
    Excludes (bucket_id, slot_id) that have a DropEvent in the window so the two lists are disjoint.
    Same shape as get_just_opened. Optional filters: date_filter, time_slots, party_sizes.
    """
    q = db.query(SlotAvailability).filter(SlotAvailability.state == "open").order_by(SlotAvailability.opened_at.desc())
    if exclude_opened_within_minutes is not None and exclude_opened_within_minutes > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=exclude_opened_within_minutes)
        recent_drop_pairs = [
            (r.bucket_id, r.slot_id)
            for r in db.query(DropEvent.bucket_id, DropEvent.slot_id)
            .filter(
                DropEvent.user_facing_opened_at >= cutoff,
                DropEvent.eligibility_evidence != "unknown",
            )
            .distinct()
            .all()
        ]
        if recent_drop_pairs:
            q = q.filter(~tuple_(SlotAvailability.bucket_id, SlotAvailability.slot_id).in_(recent_drop_pairs))
    events = q.limit(STILL_OPEN_EVENTS_LIMIT).all()

    by_date: dict[str, dict] = {}
    by_venue: dict[str, dict[str, list[tuple]]] = {}
    for r in events:
        if time_slots and _bucket_time_slot(r.bucket_id) not in time_slots:
            continue
        date_str = _bucket_date_str(r.bucket_id)
        if date_filter is not None and date_str not in date_filter:
            continue
        if date_str not in by_date:
            by_date[date_str] = {"date_str": date_str, "venues": [], "scanned_at": None}
            by_venue[date_str] = {}
        payload = json.loads(r.payload_json) if r.payload_json else {}
        if not isinstance(payload, dict):
            continue
        # slot_availability no longer stores payload_json; ensure venue_id, name, image_url from row
        if not payload.get("venue_id") and r.venue_id:
            payload["venue_id"] = r.venue_id
        if not payload.get("name") and r.venue_name:
            payload["name"] = r.venue_name
        if getattr(r, "image_url", None) and not payload.get("image_url"):
            payload["image_url"] = r.image_url
        r_market = getattr(r, "market", None) or _bucket_market(r.bucket_id)
        if not payload.get("market"):
            payload["market"] = r_market
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
        bid_val = getattr(event, "bucket_id", "")
        mkt, date_str, time_slot = _parse_bucket_id(bid_val)
        prov = (getattr(event, "provider", None) or "resy").strip() or "resy"
        rows = fetch_for_bucket(date_str, time_slot, PARTY_SIZES, provider=prov, market=mkt)
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

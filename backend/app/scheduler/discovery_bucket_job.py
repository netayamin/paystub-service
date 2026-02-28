"""
Queue + re-enqueue: each bucket has its own cooldown. Tick every DISCOVERY_TICK_SECONDS;
dispatch up to DISCOVERY_MAX_CONCURRENT_BUCKETS "ready" buckets. When a bucket finishes
it re-enters the queue (next_run_after = now + cooldown). Bucket 1 can keep updating
while bucket 27 is slow.
"""
import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone

from app.core.constants import (
    DISCOVERY_BUCKET_COOLDOWN_SECONDS,
    DISCOVERY_MAX_CONCURRENT_BUCKETS,
    DISCOVERY_PRUNE_EVERY_N_TICKS,
)
from app.db.session import SessionLocal
from app.services.discovery.buckets import (
    TIME_SLOTS,
    WINDOW_DAYS,
    all_bucket_ids,
    ensure_buckets,
    prune_old_buckets,
    run_baseline_for_bucket,
    window_start_date,
)
from app.services.discovery.buckets import _poll_one_bucket
from app.services.discovery.scan import set_discovery_job_heartbeat

logger = logging.getLogger(__name__)

# Per-bucket next-run time; when a bucket completes we set next_run_after = now + cooldown
_bucket_next_run: dict[str, datetime] = {}
_in_flight: set[str] = set()
_lock = threading.Lock()
_executor: ThreadPoolExecutor | None = None
_tick_count = 0  # for throttled retention pruning


def _get_executor() -> ThreadPoolExecutor:
    global _executor
    if _executor is None:
        _executor = ThreadPoolExecutor(
            max_workers=DISCOVERY_MAX_CONCURRENT_BUCKETS,
            thread_name_prefix="discovery_bucket",
        )
    return _executor


def _run_bucket_then_reenqueue(bid: str, date_str: str, time_slot: str) -> None:
    """Poll one bucket in its own session; on finish re-enqueue (set next_run_after) and update heartbeat."""
    now = datetime.now(timezone.utc)
    try:
        _poll_one_bucket(bid, date_str, time_slot)
        set_discovery_job_heartbeat(last_bucket_completed_at=now)
    except Exception as e:
        logger.exception("Bucket %s failed: %s", bid, e)
    finally:
        with _lock:
            _in_flight.discard(bid)
            _bucket_next_run[bid] = now + timedelta(seconds=DISCOVERY_BUCKET_COOLDOWN_SECONDS)
            in_flight = len(_in_flight)
            set_discovery_job_heartbeat(in_flight_count=in_flight)
            if in_flight == 0:
                set_discovery_job_heartbeat(finished=now, running=False)


def run_discovery_bucket_job() -> None:
    """
    One tick: prune/ensure buckets, then dispatch up to DISCOVERY_MAX_CONCURRENT_BUCKETS
    buckets that are ready (cooldown elapsed, not already in flight). Does not wait for
    them; they run in the shared executor and re-enqueue themselves when done.

    Retention: every DISCOVERY_PRUNE_EVERY_N_TICKS ticks we also prune slot_availability,
    drop_events, and availability_sessions so tables stay bounded between daily sliding-window runs.

    Baselines are set on first poll: run_poll_for_bucket treats baseline_slot_ids_json is None
    as "first run" and sets baseline = prev = curr (no separate baseline step). So we never
    do Resy calls in this thread — only cheap DB (prune, ensure_buckets) and dispatch.
    """
    global _tick_count
    today = window_start_date()
    db = SessionLocal()
    try:
        # Ensure buckets exist first so we can dispatch; then light retention.
        ensure_buckets(db, today)
        try:
            prune_old_buckets(db, today)
        except Exception as e:
            logger.warning("prune_old_buckets failed (tick continues): %s", e, exc_info=True)
            db.rollback()
        # drop_events: prune every 2 ticks to keep hot path quick (still clear regularly)
        _tick_count += 1
        if _tick_count % 2 == 0:
            try:
                from app.services.discovery.buckets import prune_old_drop_events

                prune_old_drop_events(db, today)
            except Exception as e:
                logger.warning("prune_old_drop_events failed (tick continues): %s", e, exc_info=True)
                db.rollback()
        if _tick_count >= DISCOVERY_PRUNE_EVERY_N_TICKS:
            _tick_count = 0
            try:
                from app.services.discovery.buckets import (
                    prune_old_slot_availability,
                    prune_old_sessions,
                )
                prune_old_slot_availability(db, today)
                prune_old_sessions(db, today)
            except Exception as e:
                logger.warning("prune slot_availability/sessions failed (tick continues): %s", e, exc_info=True)
                db.rollback()
    finally:
        db.close()

    buckets = list(all_bucket_ids(today))
    now = datetime.now(timezone.utc)
    min_dt = datetime.min.replace(tzinfo=timezone.utc)

    with _lock:
        # Drop state for buckets no longer in window
        current_bids = {b[0] for b in buckets}
        for bid in list(_bucket_next_run):
            if bid not in current_bids:
                del _bucket_next_run[bid]
        # New buckets are immediately ready
        for bid, _d, _t in buckets:
            if bid not in _bucket_next_run:
                _bucket_next_run[bid] = min_dt

        ready = [
            (bid, date_str, time_slot)
            for bid, date_str, time_slot in buckets
            if bid not in _in_flight and _bucket_next_run.get(bid, min_dt) <= now
        ]
        to_run = ready[:DISCOVERY_MAX_CONCURRENT_BUCKETS]

        if not to_run:
            in_flight = len(_in_flight)
            set_discovery_job_heartbeat(in_flight_count=in_flight)
            if in_flight == 0:
                set_discovery_job_heartbeat(finished=now, running=False)
            return

        for bid, date_str, time_slot in to_run:
            _in_flight.add(bid)

        set_discovery_job_heartbeat(
            started=now,
            in_flight_count=len(_in_flight),
        )

    executor = _get_executor()
    for bid, date_str, time_slot in to_run:
        executor.submit(_run_bucket_then_reenqueue, bid, date_str, time_slot)

    logger.debug("Discovery tick: dispatched %s buckets", len(to_run))


def run_sliding_window_job() -> None:
    """
    Daily: remove all CLOSED from drop_events, prune old buckets and drop_events, ensure 28 buckets, baseline the 2 new day slots.
    Aggregation is done on close only (in run_poll_for_bucket): when a drop closes we write to
    venue_metrics/market_metrics and remove it from drop_events. No daily batch aggregate.
    """
    from app.services.discovery.buckets import (
        delete_closed_drop_events,
        prune_old_drop_events,
        prune_old_market_metrics,
        prune_old_slot_availability,
        prune_old_sessions,
        prune_old_venue_metrics,
        prune_old_venue_rolling_metrics,
        prune_old_venues,
    )

    today = window_start_date()
    db = SessionLocal()
    try:
        delete_closed_drop_events(db)
        prune_old_buckets(db, today)
        prune_old_drop_events(db, today)
        prune_old_slot_availability(db, today)
        prune_old_sessions(db, today)
        prune_old_venue_rolling_metrics(db, today, keep_days=60)
        prune_old_venue_metrics(db, today)
        prune_old_market_metrics(db, today)
        prune_old_venues(db)
        ensure_buckets(db, today)
        new_day = today + timedelta(days=WINDOW_DAYS - 1)
        new_day_str = new_day.isoformat()
        for time_slot in TIME_SLOTS:
            bid = f"{new_day_str}_{time_slot}"
            run_baseline_for_bucket(db, bid, new_day_str, time_slot)
        logger.info(
            "Discovery sliding window: pruned old buckets, ensured %s buckets, baselined new day %s",
            len(all_bucket_ids(today)),
            new_day_str,
        )
    finally:
        db.close()

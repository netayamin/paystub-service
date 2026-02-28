"""
Discovery job heartbeat and fast checks (bucket pipeline only).

Heartbeat is in-memory; set by discovery_bucket_job. Fast checks use discovery_buckets last_scan_at.
Legacy discovery_scans table removed (migration 024); all discovery uses discovery_buckets + drop_events.
"""
import logging
from datetime import date, datetime, timezone

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

_job_last_started_at: datetime | None = None  # current run (when running) or last run
_job_last_finished_at: datetime | None = None
# Last *completed* run — preserved when a new run starts (which overwrites _job_last_started_at)
_job_last_completed_started_at: datetime | None = None
_job_last_completed_finished_at: datetime | None = None
_job_last_error: str | None = None
_job_last_dates_written: int | None = None
_job_running: bool = False
_last_poll_invariants: dict | None = None
# Queue model: buckets currently being polled; when any bucket completes we update this and last_bucket_completed_at
_in_flight_count: int = 0
_last_bucket_completed_at: datetime | None = None


def set_discovery_job_heartbeat(
    started: datetime | None = None,
    finished: datetime | None = None,
    error: str | None = None,
    dates_written: int | None = None,
    running: bool | None = None,
    invariants: dict | None = None,
    in_flight_count: int | None = None,
    last_bucket_completed_at: datetime | None = None,
) -> None:
    global _job_last_started_at, _job_last_finished_at, _job_last_completed_started_at, _job_last_completed_finished_at, _job_last_error, _job_last_dates_written, _job_running, _last_poll_invariants, _in_flight_count, _last_bucket_completed_at
    if started is not None:
        _job_last_started_at = started
    if finished is not None:
        _job_last_finished_at = finished
        _job_last_completed_started_at = _job_last_started_at
        _job_last_completed_finished_at = finished
    if error is not None:
        _job_last_error = error
    if dates_written is not None:
        _job_last_dates_written = dates_written
    if running is not None:
        _job_running = running
    if invariants is not None:
        _last_poll_invariants = invariants
    if in_flight_count is not None:
        _in_flight_count = in_flight_count
        _job_running = _in_flight_count > 0
    if last_bucket_completed_at is not None:
        _last_bucket_completed_at = last_bucket_completed_at


def get_discovery_job_heartbeat() -> dict:
    """Return last job run times, error (if any), in_flight_count, last_bucket_completed_at, is_job_running, last_poll_invariants. In-memory only."""
    started_at = _job_last_completed_started_at if _job_last_completed_started_at is not None else _job_last_started_at
    finished_at = _job_last_completed_finished_at if _job_last_completed_finished_at is not None else _job_last_finished_at
    out = {
        "last_job_started_at": started_at.isoformat() if started_at is not None else None,
        "last_job_finished_at": finished_at.isoformat() if finished_at is not None else None,
        "last_job_error": _job_last_error,
        "last_run_dates_written": _job_last_dates_written,
        "is_job_running": _job_running,
        "in_flight_count": _in_flight_count,
        "last_bucket_completed_at": _last_bucket_completed_at.isoformat() if _last_bucket_completed_at is not None else None,
    }
    if started_at is not None and finished_at is not None:
        started = started_at
        finished = finished_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        if finished.tzinfo is None:
            finished = finished.replace(tzinfo=timezone.utc)
        out["last_run_duration_seconds"] = max(0, (finished - started).total_seconds())
    else:
        out["last_run_duration_seconds"] = None
    # When job is running, show how long the current run has been going (use _job_last_started_at = current run)
    if _job_running and _job_last_started_at is not None:
        started = _job_last_started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        out["current_run_elapsed_seconds"] = max(0, (datetime.now(timezone.utc) - started).total_seconds())
    else:
        out["current_run_elapsed_seconds"] = None
    if _last_poll_invariants is not None:
        out["last_poll_invariants"] = _last_poll_invariants
    return out


_JOB_ALIVE_STARTED_WITHIN_MIN = 5
_FEED_UPDATING_SCAN_WITHIN_MIN = 10


def get_discovery_fast_checks(db: Session) -> dict:
    """
    Fast checks: job alive?, feed updating? Uses discovery_buckets last_scan_at only.
    """
    from app.services.discovery.buckets import get_last_scan_info_buckets, window_start_date

    heartbeat = get_discovery_job_heartbeat()
    info = get_last_scan_info_buckets(db, window_start_date())
    last_scan_at_iso = info.get("last_scan_at")
    now = datetime.now(timezone.utc)

    is_running = heartbeat.get("is_job_running") is True
    started_iso = heartbeat.get("last_job_started_at")
    finished_iso = heartbeat.get("last_job_finished_at")
    started_within_5 = False
    if started_iso:
        try:
            started_dt = datetime.fromisoformat(started_iso.replace("Z", "+00:00"))
            if started_dt.tzinfo is None:
                started_dt = started_dt.replace(tzinfo=timezone.utc)
            started_within_5 = (now - started_dt).total_seconds() < _JOB_ALIVE_STARTED_WITHIN_MIN * 60
        except (ValueError, TypeError):
            pass
    job_alive = is_running or (started_within_5 and not finished_iso)

    feed_updating = False
    if last_scan_at_iso:
        try:
            scan_dt = datetime.fromisoformat(last_scan_at_iso.replace("Z", "+00:00"))
            if scan_dt.tzinfo is None:
                scan_dt = scan_dt.replace(tzinfo=timezone.utc)
            feed_updating = (now - scan_dt).total_seconds() < _FEED_UPDATING_SCAN_WITHIN_MIN * 60
        except (ValueError, TypeError):
            pass
    # Also true if any bucket completed recently (job is actively writing)
    if not feed_updating:
        completed_iso = heartbeat.get("last_bucket_completed_at")
        if completed_iso:
            try:
                completed_dt = datetime.fromisoformat(completed_iso.replace("Z", "+00:00"))
                if completed_dt.tzinfo is None:
                    completed_dt = completed_dt.replace(tzinfo=timezone.utc)
                feed_updating = (now - completed_dt).total_seconds() < _FEED_UPDATING_SCAN_WITHIN_MIN * 60
            except (ValueError, TypeError):
                pass

    return {
        "fast_checks": {
            "job_alive": job_alive,
            "feed_updating": feed_updating,
            "job_alive_meaning": "is_job_running true, or job started within last 5 min and never finished",
            "feed_updating_meaning": "last_scan_at or last_bucket_completed_at within last 10 min",
        },
        "job_heartbeat": heartbeat,
        "discovery": {
            "last_scan_at": last_scan_at_iso,
            "total_venues_scanned": info.get("total_venues_scanned", 0),
        },
        "log_hint": "Bucket job: tick every 5s, cooldown 15s per bucket. Check bucket_health in GET /chat/watches/discovery-health.",
    }

"""
Discovery API: feed, just-opened, health and debug endpoints.

All routes are mounted under /chat so URLs stay /chat/watches/feed, /chat/watches/just-opened, etc.
"""
import asyncio
import json
import logging
import os
import sys
from datetime import date, datetime, timezone, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import func, text
from sqlalchemy.orm import Session

from app.core.constants import (
    DISCOVERY_BUCKET_JOB_ID,
    DISCOVERY_FEED_LIMIT,
    DISCOVERY_JUST_OPENED_LIMIT,
    DISCOVERY_POLL_INTERVAL_SECONDS,
    DISCOVERY_ROLLING_METRICS_LIMIT,
    JUST_OPENED_WITHIN_MINUTES,
)
from app.core.discovery_config import DISCOVERY_PARTY_SIZES, DISCOVERY_TIME_SLOTS
from app.core.nyc_hotspots import is_hotspot, list_hotspots
from app.db.session import get_db, SessionLocal
from app.models.discovery_bucket import DiscoveryBucket
from app.models.drop_event import DropEvent
from app.models.notify_preference import NotifyPreference
from app.models.slot_availability import SlotAvailability
from app.models.market_metrics import MarketMetrics
from app.models.venue_metrics import VenueMetrics
from app.models.venue_rolling_metrics import VenueRollingMetrics
from app.services.admin_service import clear_resy_db, reset_discovery_buckets, reset_all_discovery_and_metrics
from app.services.resy import search_with_availability
from app.services.resy.config import ResyConfig
from app.services.discovery import get_discovery_debug, get_discovery_fast_checks, get_discovery_job_heartbeat, get_feed_item_debug
from app.services.discovery.buckets import (
    all_bucket_ids,
    delete_closed_drop_events,
    fetch_for_bucket,
    get_baseline_snapshot,
    get_bucket_health,
    get_calendar_counts,
    get_feed,
    get_just_opened_from_buckets,
    get_last_scan_info_buckets,
    get_notifications_by_date,
    get_still_open_from_buckets,
    prune_old_buckets,
    prune_old_drop_events,
    prune_old_market_metrics,
    prune_old_sessions,
    prune_old_slot_availability,
    prune_old_venue_metrics,
    prune_old_venue_rolling_metrics,
    prune_old_venues,
    refresh_baselines_for_all_buckets,
    window_start_date,
)
from app.services.providers import get_provider, list_providers
from app.services.discovery.feed import build_feed

router = APIRouter()
logger = logging.getLogger(__name__)

def _next_scan_iso(request: Request) -> str:
    """Next discovery bucket job run time (UTC ISO). Fallback if scheduler not ready."""
    try:
        scheduler = getattr(request.app.state, "scheduler", None)
        if not scheduler:
            return (datetime.now(timezone.utc) + timedelta(seconds=DISCOVERY_POLL_INTERVAL_SECONDS)).isoformat()
        job = scheduler.get_job(DISCOVERY_BUCKET_JOB_ID)
        if job and getattr(job, "next_run_time", None):
            at = job.next_run_time
            if at.tzinfo is None:
                at = at.replace(tzinfo=timezone.utc)
            return at.isoformat()
    except Exception:
        pass
    return (datetime.now(timezone.utc) + timedelta(seconds=DISCOVERY_POLL_INTERVAL_SECONDS)).isoformat()


@router.get("/providers")
async def list_availability_providers():
    """List registered availability providers (resy, opentable, etc.). Same discovery pipeline; only fetch differs."""
    return {"providers": list_providers()}


@router.get("/watches/bucket-status")
async def bucket_status(db: Session = Depends(get_db)):
    """
    Monitor all 28 buckets without running a refresh. Returns per-bucket: bucket_id, date_str,
    time_slot, last_scan_at, baseline_count, stale. Use for dashboards or polling to see when
    baselines are filled and which buckets have been scanned recently.
    """
    try:
        bucket_health = get_bucket_health(db, window_start_date())
        stale = [b for b in bucket_health if b.get("stale")]
        return {
            "buckets": bucket_health,
            "summary": {
                "total": len(bucket_health),
                "stale_count": len(stale),
                "all_fresh": len(stale) == 0,
            },
        }
    except Exception as e:
        logger.warning("bucket_status failed: %s", e, exc_info=True)
        return {"error": str(e), "buckets": [], "summary": {}}


@router.get("/watches/discovery-health")
async def discovery_health(request: Request, db: Session = Depends(get_db)):
    """
    Monitor discovery: job_alive, feed_updating, bucket_health (28 buckets), next_scan_at.
    Stale buckets (not scanned in 4h) are excluded from just-opened/still-open; bucket_health[].stale and stale_bucket_count show which.
    """
    try:
        out = get_discovery_fast_checks(db)
        out["config"] = {"time_slots": DISCOVERY_TIME_SLOTS, "party_sizes": DISCOVERY_PARTY_SIZES}
        bucket_health = get_bucket_health(db, window_start_date())
        out["bucket_health"] = bucket_health
        stale = [b for b in bucket_health if b.get("stale")]
        out["stale_bucket_count"] = len(stale)
        out["stale_bucket_ids"] = [b["bucket_id"] for b in stale]
        out["all_buckets_fresh"] = len(stale) == 0
        if stale:
            logger.error(
                "Discovery health: %s bucket(s) stale (not run in 4+ hours): %s - major issue, check job_heartbeat and logs",
                len(stale),
                [b["bucket_id"] for b in stale],
            )
            out["critical"] = True
            out["message"] = (
                f"CRITICAL: {len(stale)} bucket(s) have not run in 4+ hours. "
                "Feed results exclude these buckets. Check job_heartbeat.error and backend logs."
            )
        out["next_scan_at"] = _next_scan_iso(request)
        return out
    except Exception as e:
        logger.warning("discovery_health failed: %s", e, exc_info=True)
        return {"error": str(e), "fast_checks": {}, "job_heartbeat": get_discovery_job_heartbeat(), "next_scan_at": _next_scan_iso(request), "log_hint": "Check backend logs."}


@router.get("/watches/resy-test")
async def resy_test(debug: bool = False, days_ahead: int = 0):
    """
    Test Resy API from this host: one search_with_availability call (same as one discovery bucket).
    Uses discovery 'today' (America/New_York). Add ?days_ahead=7 to test a future date (more likely to have slots).
    Add ?debug=1 to see raw API hit count and first hit structure.
    """
    from datetime import timedelta
    from app.services.resy.client import ResyClient
    from app.services.discovery.buckets import window_start_date
    config = ResyConfig()
    credentials_configured = config.is_configured()
    # Use same "today" as discovery (ET) so we're testing the same dates buckets use
    today = window_start_date()
    if days_ahead > 0:
        today = today + timedelta(days=min(days_ahead, 30))
    day_str = today.isoformat()
    result = search_with_availability(
        today,
        party_size=2,
        query="",
        time_filter="20:30",
        time_window_hours=3,
        per_page=100,
        max_pages=1,
    )
    if result.get("error"):
        return {
            "credentials_configured": credentials_configured,
            "resy_request": "one bucket (today, 20:30, party=2)",
            "result": {"error": result["error"], "detail": result.get("detail")},
            "hint": "Set RESY_API_KEY and RESY_AUTH_TOKEN in backend/.env on this host and restart backend.",
        }
    venues = result.get("venues") or []
    names = [v.get("name") or "(no name)" for v in venues[:5]]
    out = {
        "credentials_configured": credentials_configured,
        "resy_request": f"date={day_str}, time_filter=20:30, party=2 (discovery today, days_ahead={days_ahead})",
        "result": {
            "venue_count": len(venues),
            "sample_venue_names": names,
        },
        "hint": "If venue_count=0, Resy has no open slots for this date/time. Try ?days_ahead=7 for a future date." if len(venues) == 0 else None,
    }
    if debug:
        # Raw client call to see total hits before filtering by availability
        client = ResyClient()
        raw = client.search_with_availability(day_str, 2, time_filter="20:30", per_page=100, max_pages=1)
        hits = (raw.get("search") or {}).get("hits") or []
        first_keys = list(hits[0].keys()) if hits else []
        avail = (hits[0].get("availability") or {}) if hits else {}
        avail_keys = list(avail.keys()) if isinstance(avail, dict) else []
        slots = avail.get("slots", []) if isinstance(avail, dict) else []
        out["debug"] = {
            "raw_hit_count": len(hits),
            "first_hit_keys": first_keys,
            "availability_keys": avail_keys,
            "slots_count": len(slots) if isinstance(slots, list) else 0,
            "hint": "If raw_hit_count>0 but venue_count=0, hits have no availability.slots (Resy returned venues but no open times).",
        }
    return out


def _opentable_test_script_path() -> Path:
    """Path to scripts/opentable_test_standalone.py (backend dir = app's parent's parent)."""
    backend_dir = Path(__file__).resolve().parent.parent.parent
    return backend_dir / "scripts" / "opentable_test_standalone.py"


@router.get("/watches/opentable-test")
async def opentable_test():
    """
    Test OpenTable MultiSearchResults. Runs the HTTP call in a subprocess so the
    main server process is never blocked; /health and other endpoints stay responsive.
    curl http://localhost:8000/chat/watches/opentable-test
    """
    script = _opentable_test_script_path()
    if not script.exists():
        logger.warning("opentable-test script not found: %s", script)
        return {"ok": False, "error": "opentable_test_standalone.py not found", "hint": "Run from backend root."}

    backend_dir = script.parent.parent
    env = {**os.environ, "PYTHONPATH": str(backend_dir)}

    try:
        proc = await asyncio.create_subprocess_exec(
            sys.executable,
            str(script),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(backend_dir),
            env=env,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=35.0)
    except asyncio.TimeoutError:
        logger.warning("opentable-test subprocess timed out after 35s")
        return {"ok": False, "error": "Request timed out (35s)", "hint": "OpenTable may be slow or unreachable."}
    except Exception as e:
        logger.warning("opentable-test subprocess failed: %s", e, exc_info=True)
        return {"ok": False, "error": str(e), "hint": "Could not run test script."}

    out = (stdout or b"").decode("utf-8", errors="replace").strip()
    if stderr:
        logger.debug("opentable-test stderr: %s", stderr.decode("utf-8", errors="replace"))
    if not out:
        return {"ok": False, "error": "No output from test script", "hint": "Check server logs."}
    try:
        return json.loads(out)
    except json.JSONDecodeError as e:
        logger.warning("opentable-test invalid JSON: %s", e)
        return {"ok": False, "error": "Invalid response from test script", "raw": out[:200]}


@router.get("/watches/db-debug")
async def db_debug(request: Request, db: Session = Depends(get_db)):
    """Quick DB overview: raw counts, discovery_buckets + drop_events, last scan, job heartbeat, next_scan_at. Use for debugging logic."""
    try:
        today = date.today()
        bucket_info = get_last_scan_info_buckets(db, today)
        heartbeat = get_discovery_job_heartbeat()
        fast_checks = get_discovery_fast_checks(db)
        bucket_health = get_bucket_health(db, today)
        # Raw counts (projection = slot_availability open state)
        open_slots_count = db.query(SlotAvailability).filter(SlotAvailability.state == "open").count()
        discovery_buckets_count = db.query(DiscoveryBucket).count()
        unique_venues_open = db.query(SlotAvailability.venue_id).filter(
            SlotAvailability.state == "open",
            SlotAvailability.venue_id.isnot(None),
        ).distinct().count()
        just_opened_list = get_just_opened_from_buckets(db, limit_events=200)
        just_opened_venue_count = sum(len(day.get("venues") or []) for day in just_opened_list)
        just_opened_capped = just_opened_venue_count >= 500 or open_slots_count > 500
        all_baselines_zero = bucket_health and all((b.get("baseline_count") or 0) == 0 for b in bucket_health)
        return {
            "db": {
                "slot_availability_open_count": open_slots_count,
                "discovery_buckets_count": discovery_buckets_count,
                "unique_venues_in_open_slots": unique_venues_open,
                "just_opened_venue_count": just_opened_venue_count,
                "just_opened_capped": just_opened_capped,
            },
            "job_running": heartbeat.get("is_job_running") is True,
            "discovery_buckets": {
                "last_scan_at": bucket_info.get("last_scan_at"),
                "total_venues_scanned": bucket_info.get("total_venues_scanned", 0),
                "bucket_health": bucket_health,
                **({"baseline_all_zero_hint": "Resy returned no open slots for the dates/times polled (common for same-day/near-term). Try GET /chat/watches/resy-test?days_ahead=7 — if that shows venue_count>0, discovery will fill baselines for buckets further out in the window."} if all_baselines_zero else {}),
            },
            "fast_checks": fast_checks.get("fast_checks", {}),
            "job_heartbeat": heartbeat,
            "next_scan_at": _next_scan_iso(request),
            "hint": (
                "Tick every 2s; all buckets in parallel; compare to prev only; TTL dedupe NOTIFIED_DEDUPE_MINUTES. "
                "Feed-item-debug: GET /chat/watches/feed-item-debug?event_id=N or ?slot_id=&bucket_id= to see why an item is in the feed."
            ),
            "endpoints": {
                "bucket_status": "GET /chat/watches/bucket-status",
                "discovery_health": "GET /chat/watches/discovery-health",
                "resy_test": "GET /chat/watches/resy-test (test Resy API from this host)",
                "opentable_test": "GET /chat/watches/opentable-test (test OpenTable GQL from this host)",
                "discovery_debug": "GET /chat/watches/discovery-debug",
                "feed_item_debug": "GET /chat/watches/feed-item-debug?event_id=N or ?slot_id=&bucket_id=&fetch_curr=1",
                "feed": "GET /chat/watches/feed?since=<ISO>",
                "just_opened": f"GET /chat/watches/just-opened (just_opened = last {JUST_OPENED_WITHIN_MINUTES} min only)",
                "still_open": "GET /chat/watches/still-open",
                "refresh_discovery_baselines": "POST /chat/watches/refresh-discovery-baselines",
                "reset_discovery_buckets": "POST /chat/watches/reset-discovery-buckets",
                "reset_all": "POST /chat/watches/reset-all-discovery-and-metrics (full: discovery + metrics + cache + venues)",
                "prune_now": "POST /chat/watches/prune-now (run retention prunes now to shrink DB)",
                "baseline": "GET /chat/watches/baseline",
                "calendar_counts": "GET /chat/watches/calendar-counts",
                "providers": "GET /chat/providers (list availability providers: resy, opentable)",
            },
        }
    except Exception as e:
        logger.warning("db_debug failed: %s", e, exc_info=True)
        return {"error": str(e), "db": {}, "discovery_buckets": {}, "job_heartbeat": get_discovery_job_heartbeat(), "next_scan_at": _next_scan_iso(request), "fast_checks": {}}


def _refresh_baselines_sync() -> dict:
    """Run in thread: own DB session so we don't block the event loop or share session across threads."""
    db = SessionLocal()
    try:
        return refresh_baselines_for_all_buckets(db, window_start_date())
    finally:
        db.close()


def _run_refresh_baselines_background() -> None:
    """Fire-and-forget: run refresh in thread and log result. Called from background task."""
    try:
        result = _refresh_baselines_sync()
        logger.info(
            "refresh-discovery-baselines completed: buckets_refreshed=%s buckets_total=%s errors=%s",
            result["buckets_refreshed"],
            result["buckets_total"],
            result["errors"],
        )
        if result["errors"]:
            logger.warning("refresh-discovery-baselines had errors for buckets: %s", result["errors"])
    except Exception as e:
        logger.exception("refresh-discovery-baselines failed: %s", e)


@router.post("/watches/refresh-discovery-baselines")
async def refresh_baselines():
    """
    Start baseline refresh in the background and return immediately (202). Re-runs baseline
    for all buckets in place (current Resy search area). Takes 1–2 minutes; check server
    logs for completion. Server stays responsive.
    """
    asyncio.create_task(asyncio.to_thread(_run_refresh_baselines_background))
    return Response(
        status_code=202,
        content='{"ok": true, "message": "Baseline refresh started in background. Takes 1-2 min. Check server logs for completion."}',
        media_type="application/json",
    )


@router.post("/watches/reset-discovery-buckets")
async def reset_buckets(db: Session = Depends(get_db)):
    """Clear all discovery_buckets and drop_events. Next discovery job run (~2 min) will create fresh buckets and set baseline. Watches/chat untouched."""
    try:
        deleted = reset_discovery_buckets(db)
        return {
            "ok": True,
            "deleted": deleted,
            "message": "Discovery buckets and drop_events cleared. Next job run will create fresh baselines.",
        }
    except Exception as e:
        logger.warning("reset-discovery-buckets failed: %s", e, exc_info=True)
        return {"ok": False, "error": str(e)}


@router.post("/watches/reset-all-discovery-and-metrics")
async def reset_all_discovery_route(db: Session = Depends(get_db)):
    """
    Full reset: truncate discovery_buckets, drop_events, slot_availability, availability_sessions,
    feed_cache, venue_metrics, market_metrics, venue_rolling_metrics, venues. Keeps push_tokens and notify_preferences.
    Restart the backend after so the scheduler and job state are fresh.
    """
    try:
        result = reset_all_discovery_and_metrics(db)
        return {
            **result,
            "message": "All discovery, metrics, cache, and venues tables truncated. Restart backend for fresh jobs.",
        }
    except Exception as e:
        logger.warning("reset-all-discovery-and-metrics failed: %s", e, exc_info=True)
        return {"ok": False, "error": str(e)}


def _prune_one(db: Session, name: str, fn, *args, **kwargs):
    """Run one prune, return count or error string. Rolls back on failure so next prune can run."""
    try:
        return fn(*args, **kwargs)
    except Exception as e:
        logger.warning("prune-now %s failed: %s", name, e)
        db.rollback()
        return f"error: {e!s}"


@router.post("/watches/prune-now")
async def prune_now(db: Session = Depends(get_db)):
    """
    Run all retention prunes now so the DB only keeps data we need. Removes rows past retention
    (old buckets, old drop_events, old slot_availability, old sessions, old metrics, old venues).
    Use this when tables have grown too large and the job is slow; keeps current-window data.
    For a full reset, use POST /chat/watches/reset-discovery-buckets instead.
    """
    today = window_start_date()
    deleted = {
        "discovery_buckets": _prune_one(db, "discovery_buckets", prune_old_buckets, db, today),
        "drop_events": _prune_one(db, "drop_events", prune_old_drop_events, db, today),
        "slot_availability": _prune_one(db, "slot_availability", prune_old_slot_availability, db, today),
        "availability_sessions": _prune_one(db, "availability_sessions", prune_old_sessions, db, today),
        "venue_rolling_metrics": _prune_one(db, "venue_rolling_metrics", prune_old_venue_rolling_metrics, db, today, keep_days=60),
        "venue_metrics": _prune_one(db, "venue_metrics", prune_old_venue_metrics, db, today),
        "market_metrics": _prune_one(db, "market_metrics", prune_old_market_metrics, db, today),
        "venues": _prune_one(db, "venues", prune_old_venues, db),
    }
    errors = [k for k, v in deleted.items() if isinstance(v, str)]
    return {
        "ok": len(errors) == 0,
        "deleted": deleted,
        "message": "Retention prunes run. Only data within retention is kept. Run GET /chat/watches/row-counts to verify."
        + (f" Skipped (table missing?): {errors}." if errors else ""),
    }


@router.get("/watches/baseline")
async def get_baseline(db: Session = Depends(get_db)):
    """Initial snapshot per bucket: baseline_count, baseline_slot_ids, baseline_scanned_at. Baseline stores slot_id hashes only (no venue names)."""
    try:
        return get_baseline_snapshot(db, window_start_date())
    except Exception as e:
        logger.warning("baseline failed: %s", e, exc_info=True)
        return {"buckets": [], "hint": "", "error": str(e)}


@router.get("/watches/venue-metrics")
async def venue_metrics(
    db: Session = Depends(get_db),
    days: int = 14,
    limit: int = 100,
):
    """
    Per-venue aggregated metrics (scarcity, drop counts, avg duration) for rankings and predictions.
    Returns rows from venue_metrics for the last `days` days, ordered by scarcity_score desc.
    """
    try:
        since = date.today() - timedelta(days=days)
        rows = (
            db.query(VenueMetrics)
            .filter(VenueMetrics.window_date >= since)
            .order_by(VenueMetrics.scarcity_score.desc().nullslast(), VenueMetrics.window_date.desc())
            .limit(limit)
            .all()
        )
        return {
            "venue_metrics": [
                {
                    "venue_id": r.venue_id,
                    "venue_name": r.venue_name,
                    "window_date": r.window_date.isoformat() if r.window_date else None,
                    "computed_at": r.computed_at.isoformat() if r.computed_at else None,
                    "new_drop_count": r.new_drop_count,
                    "closed_count": r.closed_count,
                    "prime_time_drops": r.prime_time_drops,
                    "off_peak_drops": r.off_peak_drops,
                    "avg_drop_duration_seconds": r.avg_drop_duration_seconds,
                    "median_drop_duration_seconds": r.median_drop_duration_seconds,
                    "scarcity_score": r.scarcity_score,
                    "volatility_score": r.volatility_score,
                }
                for r in rows
            ],
            "days": days,
            "limit": limit,
        }
    except Exception as e:
        logger.warning("venue-metrics failed: %s", e, exc_info=True)
        return {"venue_metrics": [], "days": days, "limit": limit, "error": str(e)}


@router.get("/watches/venue-rolling-metrics")
async def venue_rolling_metrics(
    db: Session = Depends(get_db),
    limit: int = 300,
):
    """
    Per-venue rolling stats (last 14 days): drop frequency and rarity_score.
    Rarity = 0–100; higher = venue rarely has availability ("unique opportunity when it appears").
    Returns latest as_of_date row per venue, ordered by rarity_score desc.
    """
    try:
        # Latest as_of_date per venue (take most recent snapshot)
        rows = (
            db.query(VenueRollingMetrics)
            .order_by(VenueRollingMetrics.as_of_date.desc(), VenueRollingMetrics.rarity_score.desc().nullslast())
            .limit(limit * 3)
            .all()
        )
        seen: set[str] = set()
        out = []
        for r in rows:
            if r.venue_id in seen:
                continue
            seen.add(r.venue_id)
            out.append({
                "venue_id": r.venue_id,
                "venue_name": r.venue_name,
                "as_of_date": r.as_of_date.isoformat() if r.as_of_date else None,
                "window_days": r.window_days,
                "total_new_drops": r.total_new_drops,
                "days_with_drops": r.days_with_drops,
                "drop_frequency_per_day": r.drop_frequency_per_day,
                "rarity_score": r.rarity_score,
                "total_last_7d": r.total_last_7d,
                "total_prev_7d": r.total_prev_7d,
                "trend_pct": r.trend_pct,
                "availability_rate_14d": r.availability_rate_14d,
                "computed_at": r.computed_at.isoformat() if r.computed_at else None,
            })
            if len(out) >= limit:
                break
        # Sort by rarity desc so "rarely opens" venues appear first
        out.sort(key=lambda x: (x["rarity_score"] is None, -(x["rarity_score"] or 0)))
        return {"venue_rolling_metrics": out, "limit": limit}
    except Exception as e:
        logger.warning("venue-rolling-metrics failed: %s", e, exc_info=True)
        return {"venue_rolling_metrics": [], "limit": limit, "error": str(e)}


@router.get("/watches/market-metrics")
async def market_metrics(
    db: Session = Depends(get_db),
    days: int = 14,
):
    """Market-level aggregates (daily totals, etc.) for the last `days`. Good for trends and predictions."""
    try:
        since = date.today() - timedelta(days=days)
        rows = (
            db.query(MarketMetrics)
            .filter(MarketMetrics.window_date >= since, MarketMetrics.metric_type == "daily_totals")
            .order_by(MarketMetrics.window_date.desc())
            .all()
        )
        return {
            "market_metrics": [
                {
                    "window_date": r.window_date.isoformat() if r.window_date else None,
                    "metric_type": r.metric_type,
                    "value": json.loads(r.value_json) if r.value_json else None,
                    "computed_at": r.computed_at.isoformat() if r.computed_at else None,
                }
                for r in rows
            ],
            "days": days,
        }
    except Exception as e:
        logger.warning("market-metrics failed: %s", e, exc_info=True)
        return {"market_metrics": [], "days": days, "error": str(e)}


@router.get("/watches/calendar-counts")
async def calendar_counts(db: Session = Depends(get_db)):
    """Result counts per date for the 14-day calendar. by_date[date_str] = total (just_opened + still_open). Use for calendar bar graph."""
    try:
        return get_calendar_counts(db, window_start_date())
    except Exception as e:
        logger.warning("calendar-counts failed: %s", e, exc_info=True)
        return {"by_date": {}, "dates": [], "error": str(e)}


@router.get("/watches/hotlist")
async def hotlist():
    """
    NYC hotlist (hotspot) restaurant names. By default you get email/push notifications
    for drops at any of these, plus any venues you add to My Watches. Use in bookmarks UI
    to show "what you'll get notified about".
    """
    return {"hotlist": list_hotspots()}


def _normalize_venue(name: str | None) -> str:
    if not name:
        return ""
    return name.strip().lower()


def _recipient_id(request: Request) -> str:
    return (request.headers.get("X-Recipient-Id") or "default").strip() or "default"


@router.get("/venue-watches")
async def get_venue_watches(request: Request, db: Session = Depends(get_db)):
    """
    User's notify list: saved (include) and excluded (removed from default hotlist).
    Effective notify list = (hotlist ∪ watches) − excluded.
    """
    rid = _recipient_id(request)
    includes = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.preference == "include")
        .all()
    )
    excludes = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.preference == "exclude")
        .all()
    )
    # Frontend expects venue_name (display); we store normalized. Return display as title-case of normalized for includes; for hotlist we don't store display name so use normalized as-is (frontend can capitalize).
    watches = [{"id": r.id, "venue_name": r.venue_name_normalized} for r in includes]
    excluded = [{"id": r.id, "venue_name": r.venue_name_normalized} for r in excludes]
    return {"watches": watches, "excluded": excluded}


@router.post("/venue-watches")
async def add_venue_watch(request: Request, db: Session = Depends(get_db)):
    """Add a venue to your notify list (include)."""
    body = await request.json() if request.headers.get("content-type", "").startswith("application/json") else {}
    name = (body.get("venue_name") or "").strip()
    if not name:
        return Response(status_code=400, content='{"error": "venue_name required"}', media_type="application/json")
    rid = _recipient_id(request)
    norm = _normalize_venue(name)
    existing = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.venue_name_normalized == norm)
        .first()
    )
    if existing:
        if existing.preference == "exclude":
            existing.preference = "include"
            db.commit()
            return {"id": existing.id, "venue_name": norm}
        return {"id": existing.id, "venue_name": norm}
    row = NotifyPreference(recipient_id=rid, venue_name_normalized=norm, preference="include")
    db.add(row)
    db.commit()
    db.refresh(row)
    return {"id": row.id, "venue_name": norm}


@router.delete("/venue-watches/{watch_id:int}")
async def remove_venue_watch(request: Request, watch_id: int, db: Session = Depends(get_db)):
    """Remove a venue from your saved list (include)."""
    rid = _recipient_id(request)
    row = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.id == watch_id, NotifyPreference.recipient_id == rid, NotifyPreference.preference == "include")
        .first()
    )
    if not row:
        return Response(status_code=404, content='{"error": "not found"}', media_type="application/json")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.post("/venue-watches/exclude")
async def add_venue_exclude(request: Request, db: Session = Depends(get_db)):
    """Remove a venue from default hotlist notifications (exclude)."""
    body = await request.json() if request.headers.get("content-type", "").startswith("application/json") else {}
    name = (body.get("venue_name") or "").strip()
    if not name:
        return Response(status_code=400, content='{"error": "venue_name required"}', media_type="application/json")
    rid = _recipient_id(request)
    norm = _normalize_venue(name)
    existing = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.venue_name_normalized == norm)
        .first()
    )
    if existing:
        if existing.preference == "include":
            existing.preference = "exclude"
            db.commit()
            return {"id": existing.id, "venue_name": norm}
        return {"id": existing.id, "venue_name": norm}
    row = NotifyPreference(recipient_id=rid, venue_name_normalized=norm, preference="exclude")
    db.add(row)
    db.commit()
    db.refresh(row)
    return {"id": row.id, "venue_name": norm}


@router.delete("/venue-watches/exclude/{exclude_id:int}")
async def remove_venue_exclude(request: Request, exclude_id: int, db: Session = Depends(get_db)):
    """Add a venue back to default hotlist notifications (remove from excluded)."""
    rid = _recipient_id(request)
    row = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.id == exclude_id, NotifyPreference.recipient_id == rid, NotifyPreference.preference == "exclude")
        .first()
    )
    if not row:
        return Response(status_code=404, content='{"error": "not found"}', media_type="application/json")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.get("/watches/row-counts")
async def row_counts(db: Session = Depends(get_db)):
    """
    Approximate row counts for discovery tables (from pg_class, fast). Use to spot bloat.
    Large slot_availability or venue_rolling_metrics can slow just-opened; prune runs every ~50s.
    """
    tables = (
        "discovery_buckets",
        "drop_events",
        "slot_availability",
        "availability_sessions",
        "venue_rolling_metrics",
        "venue_metrics",
        "market_metrics",
        "venues",
        "feed_cache",
        "notify_preferences",
    )
    out = {}
    for t in tables:
        try:
            # Use pg_class.reltuples so we don't do full table scan (COUNT(*) is slow on big tables)
            row = db.execute(
                text("SELECT reltuples::bigint FROM pg_class WHERE relname = :name"),
                {"name": t},
            ).first()
            out[t] = int(row[0]) if row and row[0] is not None else 0
        except Exception as e:
            out[t] = {"error": str(e)}
    return {
        "row_counts": out,
        "approx": True,
        "hint": "If counts are huge: POST /chat/watches/prune-now to run retention prunes and shrink DB (keeps current data). For full clear: POST /chat/watches/reset-discovery-buckets.",
    }


@router.get("/watches/notifications-by-date")
async def notifications_by_date(
    db: Session = Depends(get_db),
    within_minutes: int | None = None,
):
    """
    New places found (just opened) grouped by date for UI notifications and alerts.
    Returns by_date[date_str] = unique venue count, total, last_scan_at.
    Frontend can poll and compare with previous response to show "new places" and trigger browser alerts.
    """
    try:
        return get_notifications_by_date(db, window_start_date(), opened_within_minutes=within_minutes)
    except Exception as e:
        logger.warning("notifications-by-date failed: %s", e, exc_info=True)
        return {"by_date": {}, "total": 0, "last_scan_at": None, "error": str(e)}


@router.get("/watches/discovery-debug")
async def discovery_debug(db: Session = Depends(get_db)):
    """Debug: bucket_health, summary, recent drops sample (name + minutes_ago)."""
    try:
        return get_discovery_debug(db)
    except Exception as e:
        logger.warning("discovery_debug failed: %s", e, exc_info=True)
        return {"bucket_health": [], "summary": {}, "hot_drops_sample": [], "error": str(e)}


@router.get("/watches/feed-item-debug")
async def feed_item_debug(
    db: Session = Depends(get_db),
    event_id: int | str | None = None,
    slot_id: str | None = None,
    bucket_id: str | None = None,
    fetch_curr: bool = False,
):
    """
    Why is this in the feed? Pass event_id=... (int or "bucket_id|slot_id") or slot_id=...&bucket_id=... .
    Returns in_baseline, in_prev, in_curr (if fetch_curr=1), emitted_at, reason.
    baseline_echo = item in baseline → should not have been emitted.
    """
    if event_id is None and not (slot_id and bucket_id):
        return {"error": "Provide event_id=... or slot_id=... and bucket_id=..."}
    out = get_feed_item_debug(db, event_id=event_id, slot_id=slot_id, bucket_id=bucket_id, fetch_curr=fetch_curr)
    if out is None:
        return {"error": "Event not found"}
    return out


@router.get("/watches/feed")
async def feed(
    db: Session = Depends(get_db),
    since: str | None = None,
    limit: int = 100,
):
    """Drop events feed. GET ?since=<ISO> returns events with opened_at > since. Poll every 10–30s for live updates."""
    since_dt = None
    if since:
        try:
            since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
            if since_dt.tzinfo is None:
                since_dt = since_dt.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    if limit < 1:
        limit = DISCOVERY_FEED_LIMIT
    elif limit > 500:
        limit = 500
    try:
        events = get_feed(db, since=since_dt, limit=limit)
        return {"events": events, "count": len(events)}
    except Exception as e:
        logger.warning("feed failed: %s", e, exc_info=True)
        return {"events": [], "count": 0, "error": str(e)}


def _first_time_from_venue(venue: dict) -> str:
    """Extract first time as HH:MM from venue availability_times."""
    times = venue.get("availability_times") or []
    if not times:
        return "—"
    t = times[0]
    if not isinstance(t, str):
        return "—"
    if " " in t:
        t = t.split(" ", 1)[1]
    return t[:5] if len(t) >= 5 else t


def _parse_since(since: str | None) -> datetime | None:
    """Parse ISO8601 since param for new-drops; return None if missing/invalid."""
    if not since or not since.strip():
        return None
    try:
        # Support with or without Z / timezone
        s = since.strip().replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, TypeError):
        return None


@router.get("/watches/new-drops")
async def new_drops(
    db: Session = Depends(get_db),
    within_minutes: int | None = None,
    since: str | None = None,
):
    """
    New restaurants (just opened) across all buckets for notifications.
    Returns only drops detected *after* `since` (ISO8601) so clients get "new the moment they happen".
    If `since` is omitted, returns all in the time window (backward compatible).
    Poll every 10–15s and pass the previous response's `at` as `since` for the next request.
    """
    minutes = within_minutes if within_minutes is not None else JUST_OPENED_WITHIN_MINUTES
    if minutes < 1 or minutes > 120:
        minutes = JUST_OPENED_WITHIN_MINUTES
    since_dt = _parse_since(since)
    # If client sent since= but we couldn't parse it, return no drops (avoid leaking full list)
    if since is not None and since.strip() and since_dt is None:
        return {"drops": [], "at": datetime.now(timezone.utc).isoformat()}
    try:
        just_opened = get_just_opened_from_buckets(
            db,
            limit_events=500,
            date_filter=None,
            opened_within_minutes=minutes,
        )
        drops = []
        for day in just_opened:
            date_str = day.get("date_str") or ""
            for v in day.get("venues") or []:
                detected_at = v.get("detected_at")
                if since_dt is not None:
                    # Only return drops we can prove are new: must have detected_at and be after since
                    if not detected_at:
                        continue
                    try:
                        dt = datetime.fromisoformat(detected_at.replace("Z", "+00:00"))
                        if dt.tzinfo is None:
                            dt = dt.replace(tzinfo=timezone.utc)
                        if dt <= since_dt:
                            continue
                    except (ValueError, TypeError):
                        continue
                name = (v.get("name") or "").strip() or "Venue"
                name_slug = name.replace(" ", "-")
                drop_id = f"just-opened-{date_str}-{name_slug}"
                time_str = _first_time_from_venue(v)
                resy_url = v.get("resy_url")
                slots = [{"date_str": date_str, "time": time_str, "resyUrl": resy_url}]
                drops.append({
                    "id": drop_id,
                    "name": name,
                    "date_str": date_str,
                    "time": time_str if time_str != "—" else None,
                    "resy_url": resy_url,
                    "detected_at": detected_at,
                    "image_url": v.get("image_url"),
                    "slots": slots,
                    "is_hotspot": is_hotspot(name),
                })
        return {"drops": drops, "at": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        logger.warning("new_drops failed: %s", e, exc_info=True)
        return {"drops": [], "at": datetime.now(timezone.utc).isoformat(), "error": str(e)}


def _parse_ints(value: str | None) -> list[int] | None:
    """Parse comma-separated ints; return None if empty or invalid."""
    if not value or not value.strip():
        return None
    out = []
    for s in value.split(","):
        s = s.strip()
        if not s:
            continue
        try:
            out.append(int(s))
        except ValueError:
            continue
    return out if out else None


@router.get("/watches/just-opened")
async def list_just_opened(
    request: Request,
    response: Response,
    db: Session = Depends(get_db),
    dates: str | None = None,
    time_slots: str | None = None,
    party_sizes: str | None = None,
    debug: str | None = None,
):
    """Just opened + still open. Optional: dates, time_slots, party_sizes. Returns all times Resy returned (no time filter)."""
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    try:
        today = window_start_date()
        date_filter = None
        if dates:
            date_filter = [s.strip() for s in dates.split(",") if s.strip()]
        time_slot_list = [s.strip() for s in (time_slots or "").split(",") if s.strip()] or None
        party_size_list = _parse_ints(party_sizes)
        response.headers["X-Discovery-Today"] = today.isoformat()
        info = get_last_scan_info_buckets(db, today)
        just_opened = get_just_opened_from_buckets(
            db,
            limit_events=DISCOVERY_JUST_OPENED_LIMIT,
            date_filter=date_filter,
            time_slots=time_slot_list,
            party_sizes=party_size_list,
            opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        still_open = get_still_open_from_buckets(
            db,
            today,
            date_filter=date_filter,
            time_slots=time_slot_list,
            party_sizes=party_size_list,
            exclude_opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        # Tag NYC hotspot venues for special notifications
        for day in just_opened:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"))
        for day in still_open:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"))

        # Feed shows only "just opened" (venues that had 0 availability and now have some).
        # Do not merge in still_open — those include baseline availability and would show places that were already open.
        feed = build_feed(just_opened, [])
        ranked_board = feed["ranked_board"]
        top_opportunities = feed["top_opportunities"]
        hot_right_now = feed["hot_right_now"]

        # Enrich feed cards with venue scarcity metrics (rarity_score, availability_rate_14d, etc.)
        # Load most-recent rolling metrics per venue (capped for scalability)
        rolling_rows = (
            db.query(VenueRollingMetrics)
            .filter(VenueRollingMetrics.venue_name.isnot(None))
            .order_by(VenueRollingMetrics.computed_at.desc())
            .limit(DISCOVERY_ROLLING_METRICS_LIMIT)
            .all()
        )
        rolling_by_name: dict[str, VenueRollingMetrics] = {}
        for rm in rolling_rows:
            key = (rm.venue_name or "").strip().lower()
            if key and key not in rolling_by_name:
                rolling_by_name[key] = rm

        def _attach_metrics(cards: list[dict]) -> None:
            for c in cards:
                nm = (c.get("name") or "").strip().lower()
                rm = rolling_by_name.get(nm)
                if rm:
                    c["rarity_score"] = rm.rarity_score
                    c["availability_rate_14d"] = rm.availability_rate_14d
                    c["days_with_drops"] = rm.days_with_drops
                    c["drop_frequency_per_day"] = rm.drop_frequency_per_day

        _attach_metrics(ranked_board)
        _attach_metrics(top_opportunities)
        _attach_metrics(hot_right_now)

        payload = {
            "just_opened": just_opened,
            "still_open": still_open,
            "ranked_board": ranked_board,
            "top_opportunities": top_opportunities,
            "hot_right_now": hot_right_now,
            **info,
            "next_scan_at": _next_scan_iso(request),
        }
        if (info.get("total_venues_scanned") or 0) == 0:
            payload["zero_venues_hint"] = (
                "Resy returned no open slots for the scanned dates/times. "
                "Check GET /chat/watches/resy-test?days_ahead=7 and RESY_API_KEY / RESY_AUTH_TOKEN in .env."
            )
        if debug and str(debug).strip() in ("1", "true", "yes"):
            just_opened_by_date = {d["date_str"]: len(d.get("venues") or []) for d in just_opened}
            still_open_by_date = {d["date_str"]: len(d.get("venues") or []) for d in still_open}
            bucket_ids = [bid for bid, _d, _t in all_bucket_ids(today)]
            rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
            def _baseline_empty(js: str | None) -> bool:
                if not js or not js.strip() or js.strip() == "[]":
                    return True
                try:
                    arr = json.loads(js)
                    return not (isinstance(arr, list) and len(arr) > 0)
                except Exception:
                    return True
            empty_baseline_buckets = [r.bucket_id for r in rows if _baseline_empty(r.baseline_slot_ids_json)]
            payload["_debug"] = {
                "date_filter_sent": date_filter,
                "just_opened_dates": list(just_opened_by_date.keys()),
                "still_open_dates": list(still_open_by_date.keys()),
                "just_opened_per_date": just_opened_by_date,
                "still_open_per_date": still_open_by_date,
                "buckets_with_empty_baseline": len(empty_baseline_buckets),
                "buckets_with_empty_baseline_ids": empty_baseline_buckets[:5],
            }
        return payload
    except Exception as e:
        logger.warning("list_just_opened failed: %s", e, exc_info=True)
        return {"just_opened": [], "still_open": [], "last_scan_at": None, "total_venues_scanned": 0, "next_scan_at": _next_scan_iso(request)}


@router.get("/watches/still-open")
async def list_still_open(
    request: Request,
    db: Session = Depends(get_db),
    dates: str | None = None,
    time_slots: str | None = None,
    party_sizes: str | None = None,
):
    """Still open only. Same query params as just-opened. Returns all times (no time filter)."""
    try:
        today = window_start_date()
        date_filter = None
        if dates:
            date_filter = [s.strip() for s in dates.split(",") if s.strip()]
        time_slot_list = [s.strip() for s in (time_slots or "").split(",") if s.strip()] or None
        party_size_list = _parse_ints(party_sizes)
        info = get_last_scan_info_buckets(db, today)
        still_open = get_still_open_from_buckets(
            db,
            today,
            date_filter=date_filter,
            time_slots=time_slot_list,
            party_sizes=party_size_list,
            exclude_opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        return {
            "still_open": still_open,
            **info,
            "next_scan_at": _next_scan_iso(request),
        }
    except Exception as e:
        logger.warning("list_still_open failed: %s", e, exc_info=True)
        return {"still_open": [], "last_scan_at": None, "total_venues_scanned": 0, "next_scan_at": _next_scan_iso(request)}


@router.get("/watches/availability")
async def get_availability(
    date_str: str,
    party_size: int = 2,
    time_filter: str | None = None,
    limit: int | None = None,
):
    """Current venues with availability for this date/party_size/time."""
    try:
        day = date.fromisoformat(date_str)
    except ValueError:
        return {"error": "Invalid date. Use YYYY-MM-DD.", "venues": []}
    if limit is not None and (limit < 1 or limit > 500):
        limit = 20
    per_page = limit if limit is not None else 100
    max_pages = 1 if limit is not None else 5
    result = search_with_availability(
        day, party_size, time_filter=time_filter or None, per_page=per_page, max_pages=max_pages
    )
    if "error" in result:
        return {"error": result["error"], "venues": []}
    venues = result.get("venues") or []
    if limit is not None and len(venues) > limit:
        venues = venues[:limit]
    return {"venues": venues}


@router.get("/booking-errors")
async def list_booking_errors(limit: int = 100):
    """List recent auto-booking attempts (table removed; returns empty)."""
    return {"attempts": []}


@router.get("/logs")
async def list_logs(limit: int = 100):
    """Recent tool call log entries (tables removed; returns empty)."""
    return {"entries": []}


@router.post("/admin/delete-closed-events")
async def admin_delete_closed_events(db: Session = Depends(get_db)):
    """Delete all CLOSED rows from drop_events (run now instead of waiting for daily job)."""
    try:
        total = delete_closed_drop_events(db, batch_size=50_000)
        return {"ok": True, "deleted": total, "message": f"Deleted {total} CLOSED drop_events."}
    except Exception as e:
        logger.exception("admin/delete-closed-events failed")
        return {"ok": False, "error": str(e)}


@router.post("/admin/clear-db")
async def admin_clear_db(db: Session = Depends(get_db)):
    """Clear all Resy/chat/discovery data. Restart backend after for a fresh scheduler."""
    try:
        deleted = clear_resy_db(db)
        return {
            "ok": True,
            "deleted": deleted,
            "message": "Database cleared. Restart the backend server so the scheduler starts completely fresh.",
        }
    except Exception as e:
        logger.exception("admin/clear-db failed")
        return {"ok": False, "error": str(e)}

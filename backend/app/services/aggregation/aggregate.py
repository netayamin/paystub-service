"""
Compute venue_metrics and market_metrics from drop_events that are about to be pruned.
Call this before prune_old_drop_events so we retain historical aggregates for
rankings, scarcity scores, and predictions.
"""
import json
import logging
import statistics
from collections import defaultdict
from datetime import date, datetime, timezone, timedelta
from typing import Any

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models.drop_event import EVENT_TYPE_CLOSED, EVENT_TYPE_NEW_DROP, DropEvent
from app.models.market_metrics import MarketMetrics
from app.models.venue_metrics import VenueMetrics
from app.models.venue_rolling_metrics import VenueRollingMetrics

logger = logging.getLogger(__name__)

METRIC_TYPE_DAILY_TOTALS = "daily_totals"
ROLLING_WINDOW_DAYS = 14


def _window_date_from_event(e: DropEvent) -> date:
    """Derive reservation date from event: slot_date or bucket_id prefix."""
    if e.slot_date:
        try:
            return datetime.strptime(e.slot_date, "%Y-%m-%d").date()
        except (ValueError, TypeError):
            pass
    if e.bucket_id and len(e.bucket_id) >= 10:
        try:
            return datetime.strptime(e.bucket_id[:10], "%Y-%m-%d").date()
        except (ValueError, TypeError):
            pass
    return date.today()


def _scarcity_score(avg_duration_seconds: float | None, new_drop_count: int, closed_count: int) -> float:
    """
    Scarcity = speed (slots disappear fast) + churn (lots of turnover) + rarity (few drops today = unique opportunity).
    Range 0–100; higher = harder to get. Suitable for ranking and ML.
    """
    avg = avg_duration_seconds if avg_duration_seconds is not None else 600.0
    # Speed: faster slots (lower avg) -> higher scarcity (max ~33)
    speed_factor = 100.0 / (1.0 + avg / 60.0)
    speed_component = speed_factor * 0.33
    # Churn: more closed events -> harder to get (max ~33)
    churn_factor = min(closed_count / 10.0, 1.0) * 50.0
    churn_component = churn_factor * 0.66
    # Rarity: fewer drops today = more "unique opportunity" that it appeared at all (max 34)
    rarity_component = 34.0 / (1.0 + new_drop_count)
    score = min(100.0, speed_component + churn_component + rarity_component)
    return round(score, 2)


def aggregate_before_prune(db: Session, today: date) -> dict[str, int]:
    """
    Aggregate all drop_events with bucket_id < today_15:00 into venue_metrics and
    market_metrics. Call this *before* prune_old_drop_events. Returns counts written.
    """
    today_str = today.isoformat()
    cutoff = f"{today_str}_15:00"
    events = (
        db.query(DropEvent)
        .filter(DropEvent.bucket_id < cutoff)
        .all()
    )
    if not events:
        logger.info("aggregate_before_prune: no events before %s, skipping", cutoff)
        return {"venue_metrics": 0, "market_metrics": 0}

    # Group by (venue_id, window_date). Use venue_id or "unknown"
    # window_date from slot_date or bucket_id
    by_venue_date: dict[tuple[str | None, date], list[Any]] = defaultdict(list)
    for e in events:
        vid = e.venue_id or "unknown"
        wd = _window_date_from_event(e)
        by_venue_date[(vid, wd)].append(e)

    # Build venue_metrics rows
    venue_rows: list[dict[str, Any]] = []
    for (venue_id, window_date), group in by_venue_date.items():
        new_drops = sum(1 for e in group if e.event_type == EVENT_TYPE_NEW_DROP)
        closed = sum(1 for e in group if e.event_type == EVENT_TYPE_CLOSED)
        prime = sum(1 for e in group if e.time_bucket == "prime")
        off_peak = sum(1 for e in group if e.time_bucket == "off_peak")
        durations = [e.drop_duration_seconds for e in group if e.drop_duration_seconds is not None]
        avg_dur = float(statistics.mean(durations)) if durations else None
        med_dur = float(statistics.median(durations)) if durations else None
        venue_name = group[0].venue_name if group else None
        scarcity = _scarcity_score(avg_dur, new_drops, closed)
        venue_rows.append({
            "venue_id": venue_id,
            "venue_name": venue_name,
            "window_date": window_date,
            "new_drop_count": new_drops,
            "closed_count": closed,
            "prime_time_drops": prime,
            "off_peak_drops": off_peak,
            "avg_drop_duration_seconds": avg_dur,
            "median_drop_duration_seconds": med_dur,
            "scarcity_score": scarcity,
            "volatility_score": None,
        })

    # Upsert venue_metrics (Postgres ON CONFLICT)
    venue_count = 0
    for row in venue_rows:
        stmt = pg_insert(VenueMetrics).values(**row)
        stmt = stmt.on_conflict_do_update(
            index_elements=["venue_id", "window_date"],
            set_={
                "venue_name": stmt.excluded.venue_name,
                "computed_at": datetime.now(timezone.utc),
                "new_drop_count": stmt.excluded.new_drop_count,
                "closed_count": stmt.excluded.closed_count,
                "prime_time_drops": stmt.excluded.prime_time_drops,
                "off_peak_drops": stmt.excluded.off_peak_drops,
                "avg_drop_duration_seconds": stmt.excluded.avg_drop_duration_seconds,
                "median_drop_duration_seconds": stmt.excluded.median_drop_duration_seconds,
                "scarcity_score": stmt.excluded.scarcity_score,
                "volatility_score": stmt.excluded.volatility_score,
            },
        )
        db.execute(stmt)
        venue_count += 1
    db.commit()

    # Market metrics: one row per window_date present in the data (daily_totals)
    window_dates = set(wd for (_, wd) in by_venue_date.keys())
    market_count = 0
    for wd in window_dates:
        day_events = [e for e in events if _window_date_from_event(e) == wd]
        new_d = sum(1 for e in day_events if e.event_type == EVENT_TYPE_NEW_DROP)
        closed_d = sum(1 for e in day_events if e.event_type == EVENT_TYPE_CLOSED)
        durations_d = [e.drop_duration_seconds for e in day_events if e.drop_duration_seconds is not None]
        avg_d = float(statistics.mean(durations_d)) if durations_d else None
        by_hour: dict[str, int] = defaultdict(int)
        for e in day_events:
            if e.opened_at is not None:
                by_hour[str(e.opened_at.hour)] += 1
        value = {
            "total_new_drops": new_d,
            "total_closed": closed_d,
            "avg_drop_duration_seconds": avg_d,
            "event_count": len(day_events),
            "weekday": wd.weekday(),
            "by_hour": dict(by_hour),
        }
        stmt = pg_insert(MarketMetrics).values(
            window_date=wd,
            metric_type=METRIC_TYPE_DAILY_TOTALS,
            value_json=json.dumps(value),
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=["window_date", "metric_type"],
            set_={
                "value_json": stmt.excluded.value_json,
                "computed_at": datetime.now(timezone.utc),
            },
        )
        db.execute(stmt)
        market_count += 1
    db.commit()

    # Venue rolling metrics: drop frequency, rarity, trend (last 7 vs prev 7), availability rate
    since = today - timedelta(days=ROLLING_WINDOW_DAYS)
    last_7_cutoff = today - timedelta(days=7)
    vm_rows = db.query(VenueMetrics).filter(VenueMetrics.window_date >= since).all()
    by_venue: dict[str, list[Any]] = defaultdict(list)
    for r in vm_rows:
        by_venue[r.venue_id].append(r)

    rolling_count = 0
    for venue_id, group in by_venue.items():
        total_new_drops = sum(r.new_drop_count for r in group)
        days_with_drops = len({r.window_date for r in group})
        venue_name = next((r.venue_name for r in group if r.venue_name), None)
        drop_frequency_per_day = total_new_drops / float(ROLLING_WINDOW_DAYS)
        rarity_score = round(100.0 / (1.0 + drop_frequency_per_day), 2)
        total_last_7d = sum(r.new_drop_count for r in group if r.window_date >= last_7_cutoff)
        total_prev_7d = sum(r.new_drop_count for r in group if r.window_date < last_7_cutoff)
        trend_pct = (
            round((total_last_7d - total_prev_7d) / total_prev_7d, 4) if total_prev_7d and total_prev_7d > 0 else None
        )
        availability_rate_14d = round(days_with_drops / float(ROLLING_WINDOW_DAYS), 4)
        stmt = pg_insert(VenueRollingMetrics).values(
            venue_id=venue_id,
            venue_name=venue_name,
            as_of_date=today,
            window_days=ROLLING_WINDOW_DAYS,
            total_new_drops=total_new_drops,
            days_with_drops=days_with_drops,
            drop_frequency_per_day=drop_frequency_per_day,
            rarity_score=rarity_score,
            total_last_7d=total_last_7d,
            total_prev_7d=total_prev_7d,
            trend_pct=trend_pct,
            availability_rate_14d=availability_rate_14d,
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=["venue_id", "as_of_date"],
            set_={
                "venue_name": stmt.excluded.venue_name,
                "computed_at": datetime.now(timezone.utc),
                "window_days": stmt.excluded.window_days,
                "total_new_drops": stmt.excluded.total_new_drops,
                "days_with_drops": stmt.excluded.days_with_drops,
                "drop_frequency_per_day": stmt.excluded.drop_frequency_per_day,
                "rarity_score": stmt.excluded.rarity_score,
                "total_last_7d": stmt.excluded.total_last_7d,
                "total_prev_7d": stmt.excluded.total_prev_7d,
                "trend_pct": stmt.excluded.trend_pct,
                "availability_rate_14d": stmt.excluded.availability_rate_14d,
            },
        )
        db.execute(stmt)
        rolling_count += 1
    db.commit()

    logger.info(
        "aggregate_before_prune: aggregated %s events -> venue_metrics=%s, market_metrics=%s, venue_rolling_metrics=%s",
        len(events),
        venue_count,
        market_count,
        rolling_count,
    )
    return {
        "venue_metrics": venue_count,
        "market_metrics": market_count,
        "venue_rolling_metrics": rolling_count,
    }

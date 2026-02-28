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
from typing import Any, Protocol

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models.drop_event import DropEvent
from app.models.market_metrics import MarketMetrics
from app.models.venue_metrics import VenueMetrics
from app.models.venue_rolling_metrics import VenueRollingMetrics

logger = logging.getLogger(__name__)

METRIC_TYPE_DAILY_TOTALS = "daily_totals"
ROLLING_WINDOW_DAYS = 14


class ClosedEventLike(Protocol):
    """In-memory closed-event data (drop_events table no longer stores CLOSED rows)."""
    venue_id: str | None
    venue_name: str | None
    drop_duration_seconds: int | None
    slot_date: str | None
    bucket_id: str | None
    session_id: int | None  # when set, we only aggregate if session.aggregated_at IS NULL and set it after


def aggregate_closed_events_into_metrics(db: Session, closed_events: list[ClosedEventLike]) -> None:
    """
    When a slot closes we write its contribution to venue_metrics and market_metrics.
    Idempotent: events with session_id are only processed if that session has aggregated_at IS NULL;
    after writing we set aggregated_at = now so the same close is never double-counted.
    """
    if not closed_events:
        return

    from app.models.availability_state import AvailabilityState

    now = datetime.now(timezone.utc)
    session_ids = [e.session_id for e in closed_events if getattr(e, "session_id", None) is not None]
    unaggregated_ids: set[int] = set()
    if session_ids:
        rows = (
            db.query(AvailabilityState.id)
            .filter(AvailabilityState.id.in_(session_ids), AvailabilityState.aggregated_at.is_(None))
            .all()
        )
        unaggregated_ids = {r[0] for r in rows}
    # Include events without session_id (backward compat) or whose session is not yet aggregated
    to_process = [
        e for e in closed_events
        if getattr(e, "session_id", None) is None or (e.session_id in unaggregated_ids)
    ]
    if not to_process:
        return

    # Group by (venue_id, window_date): list of (duration_seconds, venue_name)
    by_venue_date: dict[tuple[str, date], list[tuple[int | None, str | None]]] = defaultdict(list)
    for e in to_process:
        vid = e.venue_id or "unknown"
        wd = _window_date_from_closed_event(e)
        by_venue_date[(vid, wd)].append((e.drop_duration_seconds, e.venue_name))

    # Venue metrics: incremental upsert per (venue_id, window_date)
    for (venue_id, window_date), items in by_venue_date.items():
        durations = [d for d, _ in items if d is not None]
        venue_name = next((n for _, n in items if n), None)
        added_closed = len(items)
        added_avg = float(statistics.mean(durations)) if durations else None

        row = db.query(VenueMetrics).filter(
            VenueMetrics.venue_id == venue_id,
            VenueMetrics.window_date == window_date,
        ).first()
        if row:
            old_closed = row.closed_count or 0
            old_avg = row.avg_drop_duration_seconds
            new_closed = old_closed + added_closed
            new_drops = (row.new_drop_count or 0) + added_closed  # each CLOSED implies one NEW_DROP we're removing
            if old_avg is not None and added_avg is not None and new_closed > 0:
                new_avg = (old_avg * old_closed + added_avg * added_closed) / new_closed
            else:
                new_avg = added_avg if added_avg is not None else old_avg
            row.closed_count = new_closed
            row.new_drop_count = new_drops
            row.avg_drop_duration_seconds = new_avg
            row.scarcity_score = _scarcity_score(new_avg, new_drops, new_closed)
            row.computed_at = datetime.now(timezone.utc)
        else:
            new_avg = added_avg
            scarcity = _scarcity_score(new_avg, added_closed, added_closed)
            db.add(VenueMetrics(
                venue_id=venue_id,
                venue_name=venue_name,
                window_date=window_date,
                new_drop_count=added_closed,
                closed_count=added_closed,
                prime_time_drops=0,
                off_peak_drops=0,
                avg_drop_duration_seconds=new_avg,
                median_drop_duration_seconds=None,
                scarcity_score=scarcity,
                volatility_score=None,
            ))
    db.commit()

    # Market metrics: incremental update daily_totals per window_date
    by_date: dict[date, list[int | None]] = defaultdict(list)
    for e in to_process:
        wd = _window_date_from_closed_event(e)
        by_date[wd].append(e.drop_duration_seconds)

    for wd, durations in by_date.items():
        row = db.query(MarketMetrics).filter(
            MarketMetrics.window_date == wd,
            MarketMetrics.metric_type == METRIC_TYPE_DAILY_TOTALS,
        ).first()
        added_closed = len(durations)
        added_avg = float(statistics.mean([d for d in durations if d is not None])) if any(d is not None for d in durations) else None
        try:
            if row and row.value_json:
                value = json.loads(row.value_json)
            else:
                value = {"total_new_drops": 0, "total_closed": 0, "avg_drop_duration_seconds": None, "event_count": 0, "weekday": wd.weekday(), "by_hour": {}}
            old_closed = value.get("total_closed") or 0
            old_avg = value.get("avg_drop_duration_seconds")
            new_closed = old_closed + added_closed
            if old_avg is not None and added_avg is not None and new_closed > 0:
                new_avg = (old_avg * old_closed + added_avg * added_closed) / new_closed
            else:
                new_avg = added_avg if added_avg is not None else old_avg
            value["total_closed"] = new_closed
            value["avg_drop_duration_seconds"] = new_avg
            value["event_count"] = (value.get("event_count") or 0) + added_closed
            if row:
                row.value_json = json.dumps(value)
                row.computed_at = datetime.now(timezone.utc)
            else:
                db.add(MarketMetrics(window_date=wd, metric_type=METRIC_TYPE_DAILY_TOTALS, value_json=json.dumps(value)))
        except (TypeError, json.JSONDecodeError):
            logger.warning("aggregate_closed_events: skip market_metrics for %s", wd)
    db.commit()

    # Mark availability_state rows as aggregated so the same close is never double-counted
    if unaggregated_ids:
        db.query(AvailabilityState).filter(
            AvailabilityState.id.in_(unaggregated_ids),
        ).update({AvailabilityState.aggregated_at: now}, synchronize_session=False)
        db.commit()


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


def _window_date_from_closed_event(e: ClosedEventLike) -> date:
    """Window date for a closed event: slot_date or bucket_id prefix."""
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
    Aggregate drop_events with bucket_id < today_15:00 into venue_metrics and
    market_metrics. Call this *before* prune_old_drop_events. Bounded query so
    the job scales (no loading entire table). Returns counts written.
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
        # drop_events no longer has event_type; all rows are open drops (closed events are aggregated on close and removed)
        new_drops = len(group)
        closed = 0
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
        new_d = len(day_events)
        closed_d = 0
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
    VENUE_METRICS_LIMIT = 50_000  # cap for scalability (14 days × many venues)
    vm_rows = (
        db.query(VenueMetrics)
        .filter(VenueMetrics.window_date >= since)
        .limit(VENUE_METRICS_LIMIT)
        .all()
    )
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

#!/usr/bin/env python3
"""
Aggregate drop_events into venue_metrics, market_metrics, and venue_rolling_metrics.
Run after migrations so metrics tables exist. Uses all current drop_events.
Run: cd backend && poetry run python scripts/run_aggregate_metrics.py
Or: make migrate-metrics (runs migrate then this script).
"""
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db.session import SessionLocal
from app.services.aggregation import aggregate_before_prune


def _window_start_date() -> date:
    """First day of the 14-day discovery window (match buckets.window_start_date)."""
    now = datetime.now()
    if now.hour >= 23:
        return date.today() + timedelta(days=1)
    return date.today()


def main():
    today = _window_start_date()
    print(f"Aggregating drop_events into metrics (window_date today={today})...")
    db = SessionLocal()
    try:
        result = aggregate_before_prune(db, today)
        print(
            f"Done. venue_metrics={result['venue_metrics']}, "
            f"market_metrics={result['market_metrics']}, "
            f"venue_rolling_metrics={result.get('venue_rolling_metrics', 0)}"
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()

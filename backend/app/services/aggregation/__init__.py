"""
Aggregate drop_events into venue_metrics and market_metrics.
- When a slot closes we write to aggregation and remove from drop_events (aggregate_closed_events_into_metrics).
- venue_rolling_metrics is rebuilt daily by compute_venue_rolling_metrics (called from run_sliding_window_job).
- aggregate_before_prune is available for manual/script catch-up.
"""
from app.services.aggregation.aggregate import (
    aggregate_before_prune,
    aggregate_closed_events_into_metrics,
    compute_venue_rolling_metrics,
)

__all__ = [
    "aggregate_before_prune",
    "aggregate_closed_events_into_metrics",
    "compute_venue_rolling_metrics",
]

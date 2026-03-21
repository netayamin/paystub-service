"""
Aggregate drop_events into venue_metrics and market_metrics.
- When a slot opens we count it into venue_metrics (aggregate_open_drops_into_metrics, periodic).
- When a slot closes we write duration/closure count (aggregate_closed_events_into_metrics, real-time).
- venue_rolling_metrics is rebuilt periodically by compute_venue_rolling_metrics.
- aggregate_before_prune is available for manual/script catch-up.
"""
from app.services.aggregation.aggregate import (
    aggregate_before_prune,
    aggregate_closed_events_into_metrics,
    aggregate_open_drops_into_metrics,
    compute_venue_rolling_metrics,
)

__all__ = [
    "aggregate_before_prune",
    "aggregate_closed_events_into_metrics",
    "aggregate_open_drops_into_metrics",
    "compute_venue_rolling_metrics",
]

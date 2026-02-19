"""
Aggregate drop_events into venue_metrics and market_metrics.
- When a slot closes we write to aggregation and remove from drop_events (aggregate_closed_events_into_metrics).
- No daily batch aggregate; the daily job only prunes. aggregate_before_prune is for manual/script catch-up if needed.
"""
from app.services.aggregation.aggregate import aggregate_before_prune, aggregate_closed_events_into_metrics

__all__ = ["aggregate_before_prune", "aggregate_closed_events_into_metrics"]

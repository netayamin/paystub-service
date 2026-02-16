"""
Aggregate drop_events into venue_metrics and market_metrics before pruning.
Run from the sliding-window job so we keep valuable data for rankings and predictions.
"""
from app.services.aggregation.aggregate import aggregate_before_prune

__all__ = ["aggregate_before_prune"]

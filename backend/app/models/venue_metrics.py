"""
Per-venue, per-day aggregated metrics from drop_events. Built before pruning so we keep
historical scarcity and duration for rankings, predictions, and product value.
"""
from sqlalchemy import Column, Date, DateTime, Float, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class VenueMetrics(Base):
    __tablename__ = "venue_metrics"

    id = Column(Integer, primary_key=True, autoincrement=True)
    venue_id = Column(String(64), nullable=False, index=True)
    venue_name = Column(String(256), nullable=True)
    window_date = Column(Date, nullable=False, index=True)  # reservation date this row describes
    computed_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    # Counts (from drop_events in that window)
    new_drop_count = Column(Integer, nullable=False, default=0)
    closed_count = Column(Integer, nullable=False, default=0)
    prime_time_drops = Column(Integer, nullable=False, default=0)
    off_peak_drops = Column(Integer, nullable=False, default=0)

    # Duration (from CLOSED events)
    avg_drop_duration_seconds = Column(Float, nullable=True)
    median_drop_duration_seconds = Column(Float, nullable=True)

    # Scores (0–100 or similar; higher = harder / more volatile). Good for ranking and ML features.
    scarcity_score = Column(Float, nullable=True)
    volatility_score = Column(Float, nullable=True)

    __table_args__ = (UniqueConstraint("venue_id", "window_date", name="uq_venue_metrics_venue_window"),)

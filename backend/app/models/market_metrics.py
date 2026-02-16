"""
Market-level aggregates (daily totals, by neighborhood, by weekday). One row per window per
metric_type. Value stored as JSON for flexibility. Used for "market pulse," predictions, and content.
"""
from sqlalchemy import Column, Date, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class MarketMetrics(Base):
    __tablename__ = "market_metrics"

    id = Column(Integer, primary_key=True, autoincrement=True)
    window_date = Column(Date, nullable=False, index=True)
    metric_type = Column(String(64), nullable=False, index=True)  # e.g. daily_totals, by_neighborhood
    value_json = Column(Text, nullable=True)  # JSON: flexible structure for totals, breakdowns
    computed_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("window_date", "metric_type", name="uq_market_metrics_window_type"),
    )

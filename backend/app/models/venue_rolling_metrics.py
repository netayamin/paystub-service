"""
Per-venue rolling metrics over the last N days: drop frequency and rarity.
"Rarity" = venues that rarely have any drops; when they do, it's a unique opportunity.
"""
from sqlalchemy import Column, Date, DateTime, Float, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class VenueRollingMetrics(Base):
    __tablename__ = "venue_rolling_metrics"

    id = Column(Integer, primary_key=True, autoincrement=True)
    venue_id = Column(String(64), nullable=False, index=True)
    venue_name = Column(String(256), nullable=True)
    as_of_date = Column(Date, nullable=False, index=True)  # last date included in the window
    window_days = Column(Integer, nullable=False, default=14)
    computed_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    # Rolling counts (over window_days)
    total_new_drops = Column(Integer, nullable=False, default=0)
    days_with_drops = Column(Integer, nullable=False, default=0)  # distinct days that had at least one drop
    drop_frequency_per_day = Column(Float, nullable=True)  # total_new_drops / window_days

    # 0–100: higher = this venue rarely has availability ("unique opportunity when it appears")
    rarity_score = Column(Float, nullable=True)

    # Trend: last 7d vs previous 7d (positive = more drops lately, "easier"; negative = "getting harder")
    total_last_7d = Column(Integer, nullable=True)
    total_prev_7d = Column(Integer, nullable=True)
    trend_pct = Column(Float, nullable=True)  # (last_7d - prev_7d) / prev_7d when prev_7d > 0

    # 0.0–1.0: fraction of days in window that had at least one drop ("available 3 of 14 days")
    availability_rate_14d = Column(Float, nullable=True)

    __table_args__ = (
        UniqueConstraint("venue_id", "as_of_date", name="uq_venue_rolling_venue_as_of"),
    )

"""One row per availability window (opened_at → closed_at). For analytics and metrics."""
from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func

from app.db.base import Base


class AvailabilitySession(Base):
    __tablename__ = "availability_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    bucket_id = Column(String(20), nullable=False, index=True)
    slot_id = Column(String(64), nullable=False, index=True)
    opened_at = Column(DateTime(timezone=True), nullable=False)
    closed_at = Column(DateTime(timezone=True), nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    venue_id = Column(String(64), nullable=True)
    venue_name = Column(String(256), nullable=True)
    slot_date = Column(String(10), nullable=True)
    provider = Column(String(32), nullable=True, default="resy")
    aggregated_at = Column(DateTime(timezone=True), nullable=True)  # set when written to venue/market metrics (idempotency)

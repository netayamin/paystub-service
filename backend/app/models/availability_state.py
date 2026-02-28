"""One row per (bucket_id, slot_id): latest snapshot only. Upsert on open, update then delete on close after aggregation. No history — avoids write amplification."""
from sqlalchemy import Column, DateTime, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class AvailabilityState(Base):
    __tablename__ = "availability_state"

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

    __table_args__ = (UniqueConstraint("bucket_id", "slot_id", name="uq_availability_state_bucket_slot"),)

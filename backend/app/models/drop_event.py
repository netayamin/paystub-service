"""Open drops only: slot became available and is still available. Metrics store aggregates; we remove rows when a slot closes."""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class DropEvent(Base):
    __tablename__ = "drop_events"

    id = Column(Integer, primary_key=True, autoincrement=True)
    bucket_id = Column(String(20), nullable=False, index=True)
    slot_id = Column(String(64), nullable=False, index=True)
    opened_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    venue_id = Column(String(64), nullable=True)
    venue_name = Column(String(256), nullable=True)
    payload_json = Column(Text, nullable=True)  # full payload for rendering
    dedupe_key = Column(String(128), nullable=False, unique=True)  # bucket_id|slot_id|opened_at_minute

    closed_at = Column(DateTime(timezone=True), nullable=True)
    drop_duration_seconds = Column(Integer, nullable=True)
    time_bucket = Column(String(16), nullable=True)   # prime | off_peak
    slot_date = Column(String(10), nullable=True)     # YYYY-MM-DD of reservation
    slot_time = Column(String(32), nullable=True)    # time part of slot (e.g. 20:30:00)
    provider = Column(String(32), nullable=True, default="resy")
    neighborhood = Column(String(128), nullable=True)
    price_range = Column(String(32), nullable=True)

"""Projection: current availability state per (bucket_id, slot_id). Soft state only (no deletes)."""
from sqlalchemy import Column, DateTime, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class SlotAvailability(Base):
    __tablename__ = "slot_availability"

    bucket_id = Column(String(20), primary_key=True)
    slot_id = Column(String(64), primary_key=True)
    state = Column(String(16), nullable=False, default="open")  # open | closed
    opened_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    closed_at = Column(DateTime(timezone=True), nullable=True)
    last_seen_at = Column(DateTime(timezone=True), nullable=True)
    venue_id = Column(String(64), nullable=True)
    venue_name = Column(String(256), nullable=True)
    payload_json = Column(Text, nullable=True)
    run_id = Column(String(64), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    time_bucket = Column(String(16), nullable=True)
    slot_date = Column(String(10), nullable=True)
    slot_time = Column(String(32), nullable=True)
    provider = Column(String(32), nullable=True, default="resy")
    neighborhood = Column(String(128), nullable=True)
    price_range = Column(String(32), nullable=True)

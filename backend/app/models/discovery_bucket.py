"""Per-bucket state for discovery drops (blueprint). bucket = (date_str, time_slot); 28 buckets (14 days × 2)."""
from sqlalchemy import Column, DateTime, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class DiscoveryBucket(Base):
    __tablename__ = "discovery_buckets"

    bucket_id = Column(String(20), primary_key=True)  # e.g. "2026-02-12_15:00"
    date_str = Column(String(10), nullable=False, index=True)
    time_slot = Column(String(5), nullable=False)  # "15:00" | "19:00"
    baseline_slot_ids_json = Column(Text, nullable=True)  # JSON array of slot_id strings (original snapshot)
    prev_slot_ids_json = Column(Text, nullable=True)  # JSON array from last poll
    scanned_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

"""Per-bucket state for discovery drops. bucket = (market, date_str, time_slot); N markets × 14 days × n slots."""
from sqlalchemy import Boolean, Column, DateTime, Integer, Index, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class DiscoveryBucket(Base):
    __tablename__ = "discovery_buckets"

    bucket_id = Column(String(40), primary_key=True)  # e.g. "nyc_2026-02-12_15:00"
    date_str = Column(String(10), nullable=False, index=True)
    time_slot = Column(String(5), nullable=False)  # "15:00" | "20:30"
    market = Column(String(32), nullable=True, index=True)  # e.g. "nyc", "miami"
    baseline_slot_ids_json = Column(Text, nullable=True)  # JSON array of slot_id strings (original snapshot)
    # Venue IDs that had ≥1 open slot in the baseline snapshot — used to suppress false "drops"
    # when slot_id hashes drift (time-string format) but the venue was already bookable at baseline.
    baseline_venue_ids_json = Column(Text, nullable=True)  # JSON array of venue_id strings
    prev_slot_ids_json = Column(Text, nullable=True)  # JSON array from last poll
    scanned_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    successful_poll_count = Column(Integer, nullable=False, server_default="0")
    # True after baseline union is locked (manual baseline or N calibration polls).
    baseline_calibration_complete = Column(Boolean, nullable=False, server_default="false")
    # Successful calibration merges completed (0 until locked).
    baseline_calibration_polls = Column(Integer, nullable=False, server_default="0")

"""Open drops only: slot became available and is still available. Metrics store aggregates; we remove rows when a slot closes."""
from sqlalchemy import Boolean, Column, DateTime, Index, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class DropEvent(Base):
    __tablename__ = "drop_events"
    __table_args__ = (
        Index("ix_drop_events_user_facing_opened_at", "user_facing_opened_at"),
        Index(
            "ix_drop_events_market_user_facing_opened_at",
            "market",
            "user_facing_opened_at",
            postgresql_ops={"user_facing_opened_at": "DESC"},
        ),
        Index(
            "ix_drop_events_bucket_id_user_facing_opened_at",
            "bucket_id",
            "user_facing_opened_at",
        ),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    bucket_id = Column(String(40), nullable=False, index=True)
    slot_id = Column(String(64), nullable=False, index=True)
    opened_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    user_facing_opened_at = Column(DateTime(timezone=True), nullable=False)
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
    push_sent_at = Column(DateTime(timezone=True), nullable=True)
    market = Column(String(32), nullable=True)  # e.g. "nyc", "miami"; composite idx in __table_args__
    eligibility_evidence = Column(String(32), nullable=False, default="unknown")
    prior_snapshot_included_slot = Column(Boolean, nullable=False, default=False)
    prior_prev_slot_count = Column(Integer, nullable=False, default=0)

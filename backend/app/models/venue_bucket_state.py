"""Rolling explicit venue state per discovery bucket (BOOKABLE / UNBOOKABLE / ABSENT / UNKNOWN)."""
from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func

from app.db.base import Base


class VenueBucketState(Base):
    __tablename__ = "venue_bucket_states"

    bucket_id = Column(String(64), primary_key=True)
    venue_id = Column(String(64), primary_key=True)
    current_state = Column(String(16), nullable=False)
    previous_state = Column(String(16), nullable=True)
    consecutive_bookable_polls = Column(Integer, nullable=False, server_default="0")
    consecutive_unbookable_polls = Column(Integer, nullable=False, server_default="0")
    consecutive_absent_polls = Column(Integer, nullable=False, server_default="0")
    last_seen_at = Column(DateTime(timezone=True), nullable=True)
    last_bookable_at = Column(DateTime(timezone=True), nullable=True)
    last_unbookable_at = Column(DateTime(timezone=True), nullable=True)
    first_seen_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=True)
    venue_name_snapshot = Column(String(512), nullable=True)

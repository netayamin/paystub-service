"""Stores per-criteria watch: check for new venues every N minutes (1 or 2). Scoped by session_id."""
from sqlalchemy import Column, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class VenueWatch(Base):
    __tablename__ = "venue_watches"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(64), nullable=True, index=True)
    criteria_key = Column(String(256), nullable=False, index=True)
    interval_minutes = Column(Integer, nullable=False, default=2)
    last_checked_at = Column(DateTime(timezone=True), nullable=True)
    last_result_json = Column(Text, nullable=True)
    venue_names_json = Column(Text, nullable=True)  # optional list of venue names to watch (JSON array)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (UniqueConstraint("session_id", "criteria_key", name="uq_venue_watch_session_criteria"),)

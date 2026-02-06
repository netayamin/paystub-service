"""Notification when new venues are found by an interval watch. Shown in sidebar."""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class VenueWatchNotification(Base):
    __tablename__ = "venue_watch_notifications"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(64), nullable=False, index=True)
    criteria_summary = Column(String(255), nullable=False)
    date_str = Column(String(10), nullable=False)
    party_size = Column(Integer, nullable=False)
    time_filter = Column(String(32), nullable=True)
    new_count = Column(Integer, nullable=False)
    new_names_json = Column(Text, nullable=False)
    read_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

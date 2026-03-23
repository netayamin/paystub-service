"""Client-reported product events (push opened, tap to reserve, etc.) for conversion and ranking feedback."""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class UserBehaviorEvent(Base):
    __tablename__ = "user_behavior_events"

    id = Column(Integer, primary_key=True, autoincrement=True)
    recipient_id = Column(String(128), nullable=False, index=True)
    event_type = Column(String(64), nullable=False, index=True)
    occurred_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)

    venue_id = Column(String(64), nullable=True)
    venue_name = Column(String(256), nullable=True)
    drop_event_id = Column(Integer, nullable=True)
    notification_id = Column(Integer, nullable=True)
    time_to_action_seconds = Column(Integer, nullable=True)
    market = Column(String(32), nullable=True)
    metadata_json = Column(Text, nullable=True)

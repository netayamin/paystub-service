"""
Watch list: venues to check every hour for new availability.
"""
from sqlalchemy import Boolean, Column, DateTime, Integer, String
from sqlalchemy.sql import func

from app.db.base import Base


class WatchList(Base):
    __tablename__ = "watch_list"

    id = Column(Integer, primary_key=True, index=True)
    venue_id = Column(Integer, nullable=False, index=True)
    venue_name = Column(String(255), nullable=True)
    party_size = Column(Integer, nullable=False, default=2)
    preferred_slot = Column(String(32), nullable=True)  # lunch, dinner
    notify_only = Column(Boolean, nullable=False, default=True)  # True = notify; False = auto-book
    created_at = Column(DateTime(timezone=True), server_default=func.now())

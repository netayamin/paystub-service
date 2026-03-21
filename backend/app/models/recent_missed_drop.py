"""Append-only log of venues whose Resy slots just closed (for feed Just missed)."""
from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func

from app.db.base import Base


class RecentMissedDrop(Base):
    __tablename__ = "recent_missed_drops"

    id = Column(Integer, primary_key=True, autoincrement=True)
    venue_id = Column(String(64), nullable=True, index=True)
    venue_name = Column(String(256), nullable=False)
    image_url = Column(String(512), nullable=True)
    neighborhood = Column(String(128), nullable=True)
    market = Column(String(32), nullable=True, index=True)
    slot_time = Column(String(32), nullable=True)
    gone_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), index=True)

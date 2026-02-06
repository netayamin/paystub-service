"""
Stores last venue search result (names only) per criteria for diffing on next check.
Minimal storage to keep token usage low when comparing.
"""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class VenueSearchSnapshot(Base):
    __tablename__ = "venue_search_snapshots"

    id = Column(Integer, primary_key=True, index=True)
    criteria_key = Column(String(256), unique=True, nullable=False, index=True)
    venue_names_json = Column(Text, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

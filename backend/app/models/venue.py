"""Canonical venue record; deduplicates venue info across drop_events."""
from sqlalchemy import Column, DateTime, String
from sqlalchemy.sql import func

from app.db.base import Base


class Venue(Base):
    __tablename__ = "venues"

    venue_id = Column(String(64), primary_key=True)
    venue_name = Column(String(256), nullable=True)
    first_seen_at = Column(DateTime(timezone=True), server_default=func.now())
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

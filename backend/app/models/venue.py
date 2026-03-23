"""Canonical venue record; deduplicates venue info across drop_events."""
from sqlalchemy import Column, DateTime, String
from sqlalchemy.sql import func

from app.db.base import Base


class Venue(Base):
    __tablename__ = "venues"

    venue_id = Column(String(64), primary_key=True)
    venue_name = Column(String(256), nullable=True)
    image_url = Column(String(512), nullable=True)
    neighborhood = Column(String(128), nullable=True)
    resy_url = Column(String(512), nullable=True)
    market = Column(String(32), nullable=True)
    first_seen_at = Column(DateTime(timezone=True), server_default=func.now())
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    # Max user_facing_opened_at from any DropEvent for this venue (updated on emit). Lets us prune
    # drop_events aggressively without losing "last drop" for follows / copy.
    last_drop_opened_at = Column(DateTime(timezone=True), nullable=True)

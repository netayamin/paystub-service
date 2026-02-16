"""Precomputed feed for fast API reads."""
from sqlalchemy import Column, DateTime, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class FeedCache(Base):
    __tablename__ = "feed_cache"

    cache_key = Column(String(64), primary_key=True)
    payload_json = Column(Text, nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

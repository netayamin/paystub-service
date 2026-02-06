"""User asks to be notified when a specific venue has availability. Job runs until venue appears."""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class VenueNotifyRequest(Base):
    __tablename__ = "venue_notify_requests"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(64), nullable=False, index=True)
    title = Column(String(255), nullable=True)  # user-defined label, e.g. "Valentine's dinner"
    venue_name = Column(String(255), nullable=False)
    resy_venue_id = Column(Integer, nullable=True)  # optional; when set, matching uses ID instead of name
    date_str = Column(String(10), nullable=False)
    party_size = Column(Integer, nullable=False, default=2)
    time_filter = Column(String(32), nullable=True)
    status = Column(String(16), nullable=False, default="pending")  # pending | notified
    result_json = Column(Text, nullable=True)
    last_checked_at = Column(DateTime(timezone=True), nullable=True)  # when we last ran availability check
    created_at = Column(DateTime(timezone=True), server_default=func.now())

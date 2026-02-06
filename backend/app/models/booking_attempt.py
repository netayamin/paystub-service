"""Records of Resy auto-booking attempts (success or failure) for the Error reporter."""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class BookingAttempt(Base):
    __tablename__ = "booking_attempts"

    id = Column(Integer, primary_key=True, index=True)
    venue_name = Column(String(255), nullable=False)
    date_str = Column(String(10), nullable=False)
    party_size = Column(Integer, nullable=False)
    status = Column(String(16), nullable=False)  # success | failed
    error_message = Column(Text, nullable=True)  # null if success; reason if failed
    created_at = Column(DateTime(timezone=True), server_default=func.now())

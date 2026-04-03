"""Detected STRONG_OPEN / WEAK_OPEN (and future types); scored, notify flag for delivery layer."""
import uuid

from sqlalchemy import Boolean, Column, DateTime, Float, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.db.base import Base


class OpportunityEvent(Base):
    __tablename__ = "opportunity_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bucket_id = Column(String(64), nullable=False, index=True)
    venue_id = Column(String(64), nullable=False, index=True)
    poll_run_id = Column(UUID(as_uuid=True), nullable=True, index=True)
    event_type = Column(String(32), nullable=False, index=True)
    detected_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    opportunity_score = Column(Float, nullable=True)
    scarcity_score = Column(Float, nullable=True)
    venue_score = Column(Float, nullable=True)
    timing_score = Column(Float, nullable=True)
    ttl_score = Column(Float, nullable=True)
    confidence_score = Column(Float, nullable=True)
    freshness_score = Column(Float, nullable=True)
    reason_codes_json = Column(Text, nullable=True)
    notified = Column(Boolean, nullable=False, server_default="false")
    venue_name = Column(String(512), nullable=True)

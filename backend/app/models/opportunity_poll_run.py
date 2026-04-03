"""One discovery poll metadata for opportunity / state machine (Resy inclusive hits)."""
import uuid

from sqlalchemy import Boolean, Column, DateTime, Float, Integer, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.db.base import Base


class OpportunityPollRun(Base):
    __tablename__ = "opportunity_poll_runs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bucket_id = Column(String(64), nullable=False, index=True)
    polled_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    success = Column(Boolean, nullable=False, server_default="true")
    http_status = Column(Integer, nullable=True)
    latency_ms = Column(Integer, nullable=True)
    coverage_score = Column(Float, nullable=False, server_default="0")
    venue_hit_count = Column(Integer, nullable=False, server_default="0")
    error_count = Column(Integer, nullable=False, server_default="0")
    error_code = Column(String(64), nullable=True)
    provider = Column(String(32), nullable=False, server_default="resy")

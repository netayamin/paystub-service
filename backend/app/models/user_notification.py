"""User notification: persisted read state and metadata (scale + customization).

recipient_id: who receives (e.g. 'default' or client device/session id; later user_id when you add auth).
type: notification kind ('new_drop', etc.) for filtering and future user preferences.
read_at: NULL = unread; set when user marks as read (persisted across devices).
metadata: JSONB for type-specific payload (name, date_str, resy_url, slots, ...).
"""
from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func
from sqlalchemy.dialects.postgresql import JSONB

from app.db.base import Base


class UserNotification(Base):
    __tablename__ = "user_notifications"

    id = Column(Integer, primary_key=True, autoincrement=True)
    recipient_id = Column(String(64), nullable=False, index=True)
    type = Column(String(32), nullable=False, default="new_drop", index=True)
    read_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    payload = Column("metadata", JSONB, nullable=False, server_default="{}")  # type-specific data; column name 'metadata' in DB

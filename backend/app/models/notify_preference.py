"""User notify preferences: include (add) or exclude (remove from default hotlist).

Notify list for email/push = (hotlist ∪ included) − excluded.
"""
from sqlalchemy import Column, Integer, String

from app.db.base import Base


class NotifyPreference(Base):
    __tablename__ = "notify_preferences"

    id = Column(Integer, primary_key=True, autoincrement=True)
    recipient_id = Column(String(64), nullable=False, index=True)
    venue_name_normalized = Column(String(256), nullable=False)
    preference = Column(String(16), nullable=False, server_default="include")  # 'include' | 'exclude'

"""
Chat session: stores message history per session for context across requests.
"""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(64), unique=True, nullable=False, index=True)
    message_list = Column(Text, nullable=True)  # JSON array of ModelMessage (from pydantic_ai)
    last_venue_search_json = Column(Text, nullable=True)  # Last search result for sidebar (same as stream venues)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

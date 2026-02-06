"""Log of tool invocations for the Log tab (tool name + arguments)."""
from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class ToolCallLog(Base):
    __tablename__ = "tool_call_logs"

    id = Column(Integer, primary_key=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    tool_name = Column(String(128), nullable=False, index=True)
    arguments_json = Column(Text, nullable=True)
    session_id = Column(String(64), nullable=True, index=True)

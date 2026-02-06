"""
Dependencies for the chat agent (injected at run time).
"""
from typing import Any

from sqlalchemy.orm import Session


class ResyDeps:
    """Deps passed to the Resy agent; provides DB session and chat session_id for tools."""

    def __init__(self, db: Session, session_id: str | None = None):
        self.db = db
        self.session_id = session_id
        # Set by search_venues_with_availability so the stream can send venues to the sidebar (saves tokens).
        self.last_venue_search: list[dict[str, Any]] | None = None

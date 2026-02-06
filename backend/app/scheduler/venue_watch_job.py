"""Runs every 1 min: check for new venues for all registered watches (interval 1 or 2 min)."""

from app.db.session import SessionLocal
from app.services.venue_watch_service import run_watch_checks


def run_venue_watch_checks() -> None:
    db = SessionLocal()
    try:
        run_watch_checks(db)
    finally:
        db.close()

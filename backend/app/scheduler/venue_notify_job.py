"""Runs every 1 min: check pending venue notify requests; set notified when venue has availability."""

from app.db.session import SessionLocal
from app.services.venue_notify_service import run_venue_notify_checks


def run_venue_notify_checks_job() -> None:
    db = SessionLocal()
    try:
        run_venue_notify_checks(db)
    finally:
        db.close()

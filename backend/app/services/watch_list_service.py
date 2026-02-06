"""
Watch list: add venues to check hourly for availability.
"""
from sqlalchemy.orm import Session

from app.data.nyc_hotspots import NYC_HOTSPOTS
from app.models.watch_list import WatchList


def add_to_watch_list(
    db: Session,
    venue_id: int,
    party_size: int = 2,
    preferred_slot: str = "dinner",
    notify_only: bool = True,
) -> WatchList:
    """Add or update a venue on the watch list."""
    venue_name = None
    for h in NYC_HOTSPOTS:
        if h["venue_id"] == venue_id:
            venue_name = h["name"]
            break
    row = db.query(WatchList).filter(WatchList.venue_id == venue_id).first()
    if row:
        row.party_size = party_size
        row.preferred_slot = preferred_slot
        row.notify_only = notify_only
        if venue_name:
            row.venue_name = venue_name
    else:
        row = WatchList(
            venue_id=venue_id,
            venue_name=venue_name,
            party_size=party_size,
            preferred_slot=preferred_slot,
            notify_only=notify_only,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def get_watch_list(db: Session) -> list[dict]:
    """Return all watch list entries as dicts."""
    rows = db.query(WatchList).order_by(WatchList.created_at.desc()).all()
    return [
        {
            "id": r.id,
            "venue_id": r.venue_id,
            "venue_name": r.venue_name,
            "party_size": r.party_size,
            "preferred_slot": r.preferred_slot,
            "notify_only": r.notify_only,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]


def get_watch_list_rows(db: Session) -> list[WatchList]:
    """Return all watch list rows for the hourly job."""
    return db.query(WatchList).all()

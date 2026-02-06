"""
Resy: watch list and hourly check trigger.
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.services.watch_list_service import add_to_watch_list, get_watch_list

router = APIRouter()


class WatchListAdd(BaseModel):
    venue_id: int
    party_size: int = 2
    preferred_slot: str = "dinner"
    notify_only: bool = True


@router.get("/watch", response_model=list)
async def list_watch(db: Session = Depends(get_db)):
    """Return the user's watch list (venues checked every hour)."""
    return get_watch_list(db)


@router.post("/watch", response_model=dict)
async def add_watch(
    body: WatchListAdd,
    db: Session = Depends(get_db),
):
    """Add a venue to the hourly watch list."""
    row = add_to_watch_list(
        db,
        venue_id=body.venue_id,
        party_size=body.party_size,
        preferred_slot=body.preferred_slot,
        notify_only=body.notify_only,
    )
    return {"id": row.id, "venue_id": row.venue_id, "venue_name": row.venue_name, "party_size": row.party_size}

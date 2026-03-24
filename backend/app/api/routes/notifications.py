"""
Product analytics events from the iOS client (batch POST).

Other notification list/create APIs were web-only and have been removed.
"""
import json
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.user_behavior_event import UserBehaviorEvent

router = APIRouter()

DEFAULT_RECIPIENT_ID = "default"


def _recipient_id(
    x_recipient_id: str | None = Header(None, alias="X-Recipient-Id"),
    recipient_id: str | None = Query(None),
) -> str:
    return (x_recipient_id or recipient_id or DEFAULT_RECIPIENT_ID).strip() or DEFAULT_RECIPIENT_ID


class BehaviorEventIn(BaseModel):
    event_type: str = Field(..., min_length=1, max_length=64, description="e.g. push_opened, resy_opened")
    venue_id: str | None = Field(None, max_length=64)
    venue_name: str | None = Field(None, max_length=256)
    drop_event_id: int | None = None
    notification_id: int | None = None
    time_to_action_seconds: int | None = Field(None, ge=0, le=86400 * 7)
    market: str | None = Field(None, max_length=32)
    metadata: dict[str, Any] = Field(default_factory=dict)
    occurred_at: datetime | None = None


class BehaviorEventsRequest(BaseModel):
    recipient_id: str | None = None
    events: list[BehaviorEventIn] = Field(..., max_length=50)


@router.post("/events/behavior")
def post_behavior_events(
    body: BehaviorEventsRequest,
    db: Session = Depends(get_db),
    recipient_id: str = Depends(_recipient_id),
) -> dict[str, Any]:
    """Batch-insert lightweight product events (no PII beyond recipient_id)."""
    rid = (body.recipient_id or recipient_id).strip() or DEFAULT_RECIPIENT_ID
    created_ids: list[int] = []
    now = datetime.now(timezone.utc)
    for item in body.events:
        ts = item.occurred_at
        if ts is not None and ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        occurred = ts if ts is not None else now
        row = UserBehaviorEvent(
            recipient_id=rid,
            event_type=item.event_type.strip()[:64],
            occurred_at=occurred,
            venue_id=item.venue_id,
            venue_name=item.venue_name,
            drop_event_id=item.drop_event_id,
            notification_id=item.notification_id,
            time_to_action_seconds=item.time_to_action_seconds,
            market=item.market,
            metadata_json=json.dumps(item.metadata) if item.metadata else None,
        )
        db.add(row)
        db.flush()
        created_ids.append(row.id)
    db.commit()
    return {"ok": True, "recipient_id": rid, "inserted": len(created_ids), "ids": created_ids}

"""
User notifications API: persisted read state and metadata.

Recipient identified by X-Recipient-Id header or ?recipient_id= (default 'default').
Supports: list (with unread filter), create (from new drops), mark one read, mark all read,
and batched product/behavior events (conversion funnel).
"""
import json
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.user_behavior_event import UserBehaviorEvent
from app.models.user_notification import UserNotification

router = APIRouter()
logger = logging.getLogger(__name__)

DEFAULT_RECIPIENT_ID = "default"


def _recipient_id(
    x_recipient_id: str | None = Header(None, alias="X-Recipient-Id"),
    recipient_id: str | None = Query(None),
) -> str:
    return (x_recipient_id or recipient_id or DEFAULT_RECIPIENT_ID).strip() or DEFAULT_RECIPIENT_ID


# --- List ---


@router.get("/notifications")
def list_notifications(
    db: Session = Depends(get_db),
    recipient_id: str = Depends(_recipient_id),
    limit: int = Query(80, ge=1, le=200),
    unread_only: bool = Query(False),
) -> dict[str, Any]:
    """
    List notifications for the recipient, newest first.
    Use unread_only=true to only return unread (e.g. for badge count or filtered view).
    """
    q = db.query(UserNotification).filter(UserNotification.recipient_id == recipient_id)
    if unread_only:
        q = q.filter(UserNotification.read_at.is_(None))
    rows = q.order_by(UserNotification.created_at.desc()).limit(limit).all()
    unread_count = (
        db.query(UserNotification)
        .filter(UserNotification.recipient_id == recipient_id, UserNotification.read_at.is_(None))
        .count()
    )
    return {
        "notifications": [
            {
                "id": r.id,
                "type": r.type,
                "read": r.read_at is not None,
                "read_at": r.read_at.isoformat() if r.read_at else None,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "metadata": r.payload or {},
            }
            for r in rows
        ],
        "unread_count": unread_count,
    }


# --- Create (from new drops) ---


class CreateNotificationItem(BaseModel):
    type: str = Field("new_drop", description="Notification type")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Payload (name, date_str, resy_url, slots, ...)")


class CreateNotificationsRequest(BaseModel):
    recipient_id: str | None = None
    notifications: list[CreateNotificationItem] = Field(..., max_length=100)


@router.post("/notifications")
def create_notifications(
    body: CreateNotificationsRequest,
    db: Session = Depends(get_db),
    recipient_id: str = Depends(_recipient_id),
) -> dict[str, Any]:
    """
    Create notification rows (e.g. when frontend receives new drops).
    recipient_id in body overrides header/query when provided.
    """
    rid = (body.recipient_id or recipient_id).strip() or DEFAULT_RECIPIENT_ID
    created = []
    for item in body.notifications:
        row = UserNotification(
            recipient_id=rid,
            type=item.type or "new_drop",
            read_at=None,
            payload=item.metadata,
        )
        db.add(row)
        db.flush()
        created.append({"id": row.id, "type": row.type})
    db.commit()
    return {"created": created, "count": len(created)}


# --- Mark one read ---


@router.patch("/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    recipient_id: str = Depends(_recipient_id),
) -> dict[str, Any]:
    """Mark a single notification as read (persisted)."""
    row = (
        db.query(UserNotification)
        .filter(UserNotification.id == notification_id, UserNotification.recipient_id == recipient_id)
        .first()
    )
    if not row:
        return {"ok": False, "error": "not_found"}
    if row.read_at is None:
        row.read_at = datetime.now(timezone.utc)
        db.commit()
    return {"ok": True, "id": notification_id, "read_at": row.read_at.isoformat()}


# --- Mark all read ---


@router.post("/notifications/mark-all-read")
def mark_all_read(
    db: Session = Depends(get_db),
    recipient_id: str = Depends(_recipient_id),
) -> dict[str, Any]:
    """Mark all notifications for the recipient as read (e.g. 'Clear all' in UI)."""
    rid = recipient_id.strip() or DEFAULT_RECIPIENT_ID
    now = datetime.now(timezone.utc)
    updated = (
        db.query(UserNotification)
        .filter(UserNotification.recipient_id == rid, UserNotification.read_at.is_(None))
        .update({UserNotification.read_at: now}, synchronize_session=False)
    )
    db.commit()
    return {"ok": True, "recipient_id": rid, "marked_count": updated}


# --- Behavior / conversion events (client POST) ---


class BehaviorEventIn(BaseModel):
    event_type: str = Field(..., min_length=1, max_length=64, description="e.g. push_opened, feed_card_tap, resy_opened")
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


@router.post("/notifications/behavior-events")
def post_behavior_events(
    body: BehaviorEventsRequest,
    db: Session = Depends(get_db),
    recipient_id: str = Depends(_recipient_id),
) -> dict[str, Any]:
    """
    Batch-insert lightweight product events (no PII beyond recipient_id).
    Idempotent at app level is not required; clients may retry with same payload.
    """
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

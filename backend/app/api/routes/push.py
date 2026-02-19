"""Push notification registration: device tokens for new-drop alerts."""
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.push_token import PushToken

router = APIRouter()
logger = logging.getLogger(__name__)


class RegisterPushBody(BaseModel):
    device_token: str = Field(..., min_length=1, max_length=256, description="APNs device token (hex string)")
    platform: str = Field(default="ios", pattern="^(ios|android)$")


@router.post("/push/register")
def register_push_token(body: RegisterPushBody, db: Session = Depends(get_db)):
    """
    Register a device for push notifications (new drops).
    Call this from the iOS app after receiving the device token from APNs.
    Idempotent: same token is upserted (updated_at refreshed).
    """
    token_str = body.device_token.strip()
    existing = db.query(PushToken).filter(PushToken.device_token == token_str).first()
    if existing:
        existing.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"ok": True, "message": "Token already registered"}
    db.add(PushToken(device_token=token_str, platform=body.platform))
    db.commit()
    logger.info("Registered push token for platform=%s", body.platform)
    return {"ok": True, "message": "Token registered"}

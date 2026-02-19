"""
Send push notifications for new drops: every minute, find drop_events that haven't
had push_sent_at set, send to registered device tokens (APNs) and/or email (Resend).
Email is used when you don't have an Apple Developer account yet; set NOTIFY_EMAIL + RESEND_API_KEY.
"""
import logging
from datetime import datetime, timezone, timedelta

from app.config import settings
from app.db.session import SessionLocal
from app.models.drop_event import DropEvent
from app.models.push_token import PushToken
from app.services.email_notify import send_new_drops_email
from app.services.push import send_push_for_new_drops

logger = logging.getLogger(__name__)

# Only send for drops opened in the last N minutes (avoid sending for very old backlog)
PUSH_WINDOW_MINUTES = 15


def run_push_for_new_drops_job() -> None:
    db = SessionLocal()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=PUSH_WINDOW_MINUTES)
        unsent = (
            db.query(DropEvent)
            .filter(DropEvent.push_sent_at.is_(None), DropEvent.opened_at >= cutoff)
            .order_by(DropEvent.opened_at.asc())
            .limit(100)  # cap per run to avoid burst
            .all()
        )
        if not unsent:
            return
        now = datetime.now(timezone.utc)
        tokens = [r.device_token for r in db.query(PushToken).all()]
        notify_email = (settings.notify_email or "").strip()

        # 1) Email digest (no Apple Developer account needed)
        if notify_email:
            drops_payload = [
                {"venue_name": r.venue_name, "slot_date": r.slot_date, "slot_time": r.slot_time}
                for r in unsent
            ]
            if send_new_drops_email(notify_email, drops_payload):
                pass  # will mark push_sent_at below for all

        # 2) APNs push if we have tokens
        if tokens:
            sent_count = 0
            for row in unsent:
                n = send_push_for_new_drops(
                    device_tokens=tokens,
                    venue_name=row.venue_name or "A table",
                    slot_date=row.slot_date,
                    slot_time=row.slot_time,
                )
                sent_count += n
                row.push_sent_at = now
            logger.info("Push job: sent %s notifications for %s new drops to %s devices", sent_count, len(unsent), len(tokens))
        else:
            for row in unsent:
                row.push_sent_at = now
            if notify_email:
                logger.info("Push job: emailed %s new drops to %s (no push tokens)", len(unsent), notify_email)
            else:
                logger.debug("No push tokens or email; marked %s new drops as sent", len(unsent))
        db.commit()
    except Exception as e:
        logger.exception("Push job failed: %s", e)
        db.rollback()
    finally:
        db.close()

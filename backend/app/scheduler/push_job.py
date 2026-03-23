"""
Send push notifications for new drops: every minute, find drop_events that haven't
had push_sent_at set (canonical `user_facing_opened_at` window), send to registered device tokens (APNs).

Push is sent only when a drop is for a restaurant on the notify list.
Notify list = (hotlist ∪ user-added includes) − user exclusions (from notify_preferences).
"""
import json
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, tuple_

from app.core.nyc_hotspots import is_hotspot, list_hotspots
from app.db.session import SessionLocal

from app.models.drop_event import DropEvent
from app.models.notify_preference import NotifyPreference
from app.models.push_token import PushToken
from app.models.venue_rolling_metrics import VenueRollingMetrics
from app.services.discovery.eligibility import push_notification_allowed
from app.services.discovery.push_scoring import (
    push_delivery_score,
    should_use_rare_opening_title,
)
from app.services.discovery.venue_profile import normalize_http_url
from app.services.push import send_push_for_new_drops

logger = logging.getLogger(__name__)

# Only send for drops opened in the last N minutes (avoid sending for very old backlog)
PUSH_WINDOW_MINUTES = 15

# Recipient id (same as frontend default)
PUSH_RECIPIENT_ID = "default"


def _latest_rarity_by_venue_id(db, venue_ids: set[str]) -> dict[str, float]:
    """Most recent venue_rolling_metrics row per venue_id (by as_of_date)."""
    if not venue_ids:
        return {}
    agg = (
        db.query(
            VenueRollingMetrics.venue_id,
            func.max(VenueRollingMetrics.as_of_date).label("mx"),
        )
        .filter(VenueRollingMetrics.venue_id.in_(venue_ids))
        .group_by(VenueRollingMetrics.venue_id)
        .all()
    )
    if not agg:
        return {}
    pairs = [(vid, mx) for vid, mx in agg]
    rows = (
        db.query(VenueRollingMetrics)
        .filter(tuple_(VenueRollingMetrics.venue_id, VenueRollingMetrics.as_of_date).in_(pairs))
        .all()
    )
    return {r.venue_id: float(r.rarity_score or 0.0) for r in rows}


def _normalize_venue(name: str | None) -> str:
    if not name:
        return ""
    return name.strip().lower()


def run_push_for_new_drops_job() -> None:
    db = SessionLocal()
    try:
        # Notify list = (hotlist ∪ includes) − excludes from notify_preferences
        watched_names = set()
        explicit_includes: set[str] = set()
        try:
            explicit_includes = {
                r.venue_name_normalized
                for r in db.query(NotifyPreference).filter(
                    NotifyPreference.recipient_id == PUSH_RECIPIENT_ID,
                    NotifyPreference.preference == "include",
                ).all()
            }
            excludes = {
                r.venue_name_normalized
                for r in db.query(NotifyPreference).filter(
                    NotifyPreference.recipient_id == PUSH_RECIPIENT_ID,
                    NotifyPreference.preference == "exclude",
                ).all()
            }
            for name in list_hotspots():
                watched_names.add(_normalize_venue(name))
            watched_names |= explicit_includes
            watched_names -= excludes
        except Exception as e:
            logger.warning("Push job: could not load notify preferences (using hotlist only): %s", e)
            explicit_includes = set()
            for name in list_hotspots():
                watched_names.add(_normalize_venue(name))
        if not watched_names:
            logger.debug("Push job: no venue watches for recipient %s; skipping (email/push only for watched restaurants)", PUSH_RECIPIENT_ID)
            return

        cutoff = datetime.now(timezone.utc) - timedelta(minutes=PUSH_WINDOW_MINUTES)
        unsent = (
            db.query(DropEvent)
            .filter(DropEvent.push_sent_at.is_(None), DropEvent.user_facing_opened_at >= cutoff)
            .order_by(DropEvent.user_facing_opened_at.asc())
            .limit(100)  # cap per run to avoid burst
            .all()
        )
        # Send email/push only for drops at watched venues (saved list + hotlist); use is_hotspot for fuzzy name match
        unsent = [
            r
            for r in unsent
            if push_notification_allowed(getattr(r, "eligibility_evidence", None))
            and (
                _normalize_venue(r.venue_name) in watched_names
                or is_hotspot(r.venue_name)
            )
        ]
        if not unsent:
            return

        vids = {r.venue_id for r in unsent if getattr(r, "venue_id", None)}
        rarity_map = _latest_rarity_by_venue_id(db, vids)

        def _score(r: DropEvent) -> float:
            return push_delivery_score(
                _normalize_venue(r.venue_name),
                r.venue_name,
                r.venue_id,
                getattr(r, "eligibility_evidence", None),
                explicit_includes=explicit_includes,
                rarity_by_venue_id=rarity_map,
                is_hotspot_fn=is_hotspot,
            )

        unsent.sort(key=lambda r: (-_score(r), r.user_facing_opened_at))

        now = datetime.now(timezone.utc)
        tokens = [r.device_token for r in db.query(PushToken).all()]

        # APNs push if we have tokens
        if tokens:
            sent_count = 0
            for row in unsent:
                # Extract resy_url from stored payload for deep-link in push notification
                resy_url = None
                if row.payload_json:
                    try:
                        p = json.loads(row.payload_json)
                        raw_u = p.get("resy_url") or p.get("resyUrl") or p.get("book_url")
                        if isinstance(raw_u, str) and raw_u.strip():
                            resy_url = normalize_http_url(raw_u.strip())
                    except Exception:
                        pass
                vn = _normalize_venue(row.venue_name)
                highlight = should_use_rare_opening_title(
                    vn,
                    row.venue_name,
                    row.venue_id,
                    explicit_includes=explicit_includes,
                    rarity_by_venue_id=rarity_map,
                    is_hotspot_fn=is_hotspot,
                )
                n = send_push_for_new_drops(
                    device_tokens=tokens,
                    venue_name=row.venue_name or "A table",
                    slot_date=row.slot_date,
                    slot_time=row.slot_time,
                    resy_url=resy_url,
                    highlight_rare=highlight,
                )
                sent_count += n
                row.push_sent_at = now
            logger.info("Push job: sent %s notifications for %s new drops to %s devices", sent_count, len(unsent), len(tokens))
        else:
            for row in unsent:
                row.push_sent_at = now
            logger.debug("No push tokens; marked %s new drops as sent", len(unsent))
        db.commit()
    except Exception as e:
        logger.exception("Push job failed: %s", e)
        db.rollback()
    finally:
        db.close()

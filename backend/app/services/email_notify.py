"""
Send new-drop notifications by email via Resend (no Apple Developer account needed).
Set NOTIFY_EMAIL and RESEND_API_KEY in .env. From address: NOTIFY_FROM or Resend default.
"""
import logging
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)


def _from_address() -> str:
    return (settings.notify_from or "").strip() or "Drop Feed <onboarding@resend.dev>"

RESEND_API = "https://api.resend.com/emails"


def send_new_drops_email(
    to_email: str,
    drops: list[dict[str, Any]],
    *,
    from_email: str | None = None,
) -> bool:
    """
    Send a single digest email listing new drops. Each drop can have venue_name, slot_date, slot_time.
    Returns True if sent, False if skipped or failed.
    """
    to_email = (to_email or "").strip()
    if not to_email or not drops:
        return False
    api_key = (settings.resend_api_key or "").strip()
    if not api_key:
        logger.debug("RESEND_API_KEY not set; skipping email notify")
        return False
    from_addr = (from_email or "").strip() or _from_address()
    lines = ["New tables just opened:", ""]
    for d in drops[:25]:  # cap at 25
        name = (d.get("venue_name") or "A table").strip()
        date = (d.get("slot_date") or "").strip()
        time = (d.get("slot_time") or "").strip()
        if time and len(time) > 5:
            time = time[:5]  # 20:30:00 -> 20:30
        line = f"• {name}"
        if date or time:
            line += f" — {date} {time}".strip()
        lines.append(line)
    body = "\n".join(lines)
    html = f"<pre style='font-family:sans-serif'>{body}</pre>"
    payload = {
        "from": from_addr,
        "to": [to_email],
        "subject": f"Drop Feed: {len(drops)} new table{'s' if len(drops) != 1 else ''}",
        "html": html,
    }
    try:
        r = httpx.post(
            RESEND_API,
            json=payload,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            timeout=10.0,
        )
        if r.is_success:
            logger.info("Email sent to %s for %s new drops", to_email, len(drops))
            return True
        logger.warning("Resend API error: %s %s", r.status_code, r.text[:200])
        return False
    except Exception as e:
        logger.exception("Failed to send new-drops email: %s", e)
        return False

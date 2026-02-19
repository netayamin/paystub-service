"""
Send new-drop notifications by email via SMTP (Google Gmail or other).
Set NOTIFY_EMAIL, SMTP_USER, SMTP_PASSWORD in .env. Use a Gmail App Password (not your normal password).
"""
import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any

from app.config import settings

logger = logging.getLogger(__name__)


def _from_address() -> str:
    if (settings.notify_from or "").strip():
        return settings.notify_from.strip()
    user = (settings.smtp_user or "").strip()
    if user:
        return f"Drop Feed <{user}>"
    return "Drop Feed <noreply@localhost>"


def send_new_drops_email(
    to_email: str,
    drops: list[dict[str, Any]],
    *,
    from_email: str | None = None,
) -> bool:
    """
    Send a single digest email listing new drops via SMTP. Each drop can have venue_name, slot_date, slot_time.
    Returns True if sent, False if skipped or failed.
    """
    to_email = (to_email or "").strip()
    if not to_email or not drops:
        return False
    user = (settings.smtp_user or "").strip()
    password = (settings.smtp_password or "").strip()
    if not user or not password:
        logger.debug("SMTP_USER or SMTP_PASSWORD not set; skipping email notify")
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
    subject = f"Drop Feed: {len(drops)} new table{'s' if len(drops) != 1 else ''}"
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_email
    msg.attach(MIMEText(body, "plain"))
    msg.attach(MIMEText(f"<pre style='font-family:sans-serif'>{body}</pre>", "html"))
    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as server:
            server.starttls()
            server.login(user, password)
            server.sendmail(user, [to_email], msg.as_string())
        logger.info("Email sent to %s for %s new drops", to_email, len(drops))
        return True
    except Exception as e:
        logger.exception("Failed to send new-drops email: %s", e)
        return False

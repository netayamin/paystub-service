"""
Email notifications for new drops. No Apple Developer account needed.
Set NOTIFICATION_EMAIL and SMTP_* in env. If not set, no-op.
"""
import logging
import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

logger = logging.getLogger(__name__)


def _smtp_config():
    to_email = os.getenv("NOTIFICATION_EMAIL", "").strip()
    host = os.getenv("SMTP_HOST", "smtp.gmail.com").strip()
    port = int(os.getenv("SMTP_PORT", "587"))
    user = os.getenv("SMTP_USER", "").strip()
    password = os.getenv("SMTP_PASSWORD", "").strip() or os.getenv("SMTP_APP_PASSWORD", "").strip()
    from_email = os.getenv("EMAIL_FROM", "").strip() or user
    if not to_email or not user or not password:
        return None
    return {
        "to_email": to_email,
        "host": host,
        "port": port,
        "user": user,
        "password": password,
        "from_email": from_email,
    }


def send_email_for_new_drops(drops: list) -> bool:
    """
    Send one email listing new drops (venue name, date, time).
    drops: list of DropEvent-like objects with venue_name, slot_date, slot_time.
    Returns True if sent, False if skipped (no config or error).
    """
    cfg = _smtp_config()
    if not cfg or not drops:
        return False
    lines = []
    for d in drops:
        name = getattr(d, "venue_name", None) or "A table"
        date_str = getattr(d, "slot_date", None) or ""
        time_str = getattr(d, "slot_time", None) or ""
        if date_str or time_str:
            lines.append(f"• {name} — {date_str} {time_str}".strip())
        else:
            lines.append(f"• {name}")
    subject = f"New drops: {len(drops)} restaurant(s) just opened"
    body = "Tables that just opened:\n\n" + "\n".join(lines)
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = cfg["from_email"]
    msg["To"] = cfg["to_email"]
    msg.attach(MIMEText(body, "plain"))
    try:
        with smtplib.SMTP(cfg["host"], cfg["port"]) as server:
            server.starttls()
            server.login(cfg["user"], cfg["password"])
            server.sendmail(cfg["from_email"], [cfg["to_email"]], msg.as_string())
        logger.info("Email sent to %s for %s new drops", cfg["to_email"], len(drops))
        return True
    except Exception as e:
        logger.warning("Email notify failed: %s", e, exc_info=True)
        return False

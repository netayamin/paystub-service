"""
Send push notifications via Apple Push Notification service (APNs).
Requires APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, and APNS_KEY_P8_PATH or APNS_KEY_P8_BASE64 in env.
If not configured, send_push_for_drop and send_apns no-op (log and return).
"""
import logging
import os
import time
from pathlib import Path

import httpx
import jwt

logger = logging.getLogger(__name__)

# APNs host: sandbox for dev builds, production for release
APNS_SANDBOX = "https://api.sandbox.push.apple.com"
APNS_PRODUCTION = "https://api.push.apple.com"

# JWT cache: (token_string, expiry_epoch). APNs accepts tokens with iat within last hour.
_jwt_cache: tuple[str, float] | None = None
_JWT_EXPIRY_SECONDS = 55 * 60  # refresh a bit before 1 hour


def _load_p8_key() -> str | None:
    """Load .p8 key from APNS_KEY_P8_PATH or APNS_KEY_P8_BASE64. Return None if not set."""
    base64_content = os.getenv("APNS_KEY_P8_BASE64")
    if base64_content:
        import base64
        try:
            return base64.b64decode(base64_content).decode("utf-8")
        except Exception as e:
            logger.warning("APNS_KEY_P8_BASE64 decode failed: %s", e)
            return None
    path = os.getenv("APNS_KEY_P8_PATH")
    if path and Path(path).exists():
        try:
            return Path(path).read_text(encoding="utf-8")
        except Exception as e:
            logger.warning("APNS_KEY_P8_PATH read failed: %s", e)
            return None
    return None


def _get_apns_jwt() -> str | None:
    """Build and cache JWT for APNs. Returns None if config missing."""
    global _jwt_cache
    key_id = os.getenv("APNS_KEY_ID")
    team_id = os.getenv("APNS_TEAM_ID")
    if not key_id or not team_id:
        return None
    p8 = _load_p8_key()
    if not p8:
        return None
    now = time.time()
    if _jwt_cache and _jwt_cache[1] > now:
        return _jwt_cache[0]
    try:
        token = jwt.encode(
            {"iss": team_id, "iat": int(now)},
            p8,
            algorithm="ES256",
            headers={"alg": "ES256", "kid": key_id},
        )
        if isinstance(token, bytes):
            token = token.decode("utf-8")
        _jwt_cache = (token, now + _JWT_EXPIRY_SECONDS)
        return token
    except Exception as e:
        logger.warning("APNs JWT build failed: %s", e, exc_info=True)
        return None


def send_apns(device_token: str, title: str, body: str, bundle_id: str | None = None) -> bool:
    """
    Send one push notification to an iOS device via APNs.
    Returns True if sent successfully, False otherwise (config missing or APNs error).
    """
    bundle_id = bundle_id or os.getenv("APNS_BUNDLE_ID")
    if not bundle_id:
        logger.debug("APNS_BUNDLE_ID not set; skipping push")
        return False
    jwt_token = _get_apns_jwt()
    if not jwt_token:
        logger.debug("APNs not configured (key/team/bundle); skipping push")
        return False
    use_sandbox = os.getenv("APNS_USE_SANDBOX", "true").lower() in ("1", "true", "yes")
    base_url = APNS_SANDBOX if use_sandbox else APNS_PRODUCTION
    url = f"{base_url}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {jwt_token}",
        "apns-topic": bundle_id,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
        }
    }
    try:
        with httpx.Client(http2=True, timeout=10.0) as client:
            resp = client.post(url, json=payload, headers=headers)
        if resp.status_code == 200:
            return True
        logger.warning("APNs returned %s for token %s...: %s", resp.status_code, device_token[:20], resp.text)
        return False
    except Exception as e:
        logger.warning("APNs request failed: %s", e, exc_info=True)
        return False


def send_push_for_new_drops(
    device_tokens: list[str],
    venue_name: str,
    slot_date: str | None = None,
    slot_time: str | None = None,
    bundle_id: str | None = None,
) -> int:
    """
    Send "New drop: {venue_name}" push to all given device tokens.
    Returns count of successful sends.
    """
    title = "New drop"
    body = venue_name
    if slot_date or slot_time:
        parts = [p for p in (slot_date, slot_time) if p]
        if parts:
            body = f"{venue_name} — {', '.join(parts)}"
    sent = 0
    for token in device_tokens:
        if send_apns(token, title, body, bundle_id=bundle_id):
            sent += 1
    return sent

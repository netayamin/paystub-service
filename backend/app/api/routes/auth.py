"""
Phone OTP auth for mobile.

Dev: OTP is logged; set AUTH_OTP_FIXED=123456 in .env for predictable testing.
Production: replace the logger line with Twilio / SNS (or similar).
"""
from __future__ import annotations

import asyncio
import logging
import os
import secrets
import time

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

router = APIRouter()

_lock = asyncio.Lock()
# phone_e164 -> (code, expires_at_unix)
_otp_by_phone: dict[str, tuple[str, float]] = {}
# access_token -> (phone_e164, expires_at_unix)
_sessions: dict[str, tuple[str, float]] = {}

OTP_TTL_SEC = 600
SESSION_TTL_SEC = 60 * 60 * 24 * 30


def _normalize_phone_e164(raw: str) -> str:
    s = (raw or "").strip()
    digits = "".join(c for c in s if c.isdigit())
    if len(digits) == 10:
        return "+1" + digits
    if len(digits) == 11 and digits.startswith("1"):
        return "+" + digits
    if s.startswith("+") and len(digits) >= 10:
        return "+" + digits
    raise ValueError("invalid phone")


def _purge_expired_unlocked(now: float) -> None:
    dead_otp = [k for k, (_, exp) in _otp_by_phone.items() if exp < now]
    for k in dead_otp:
        del _otp_by_phone[k]
    dead_s = [k for k, (_, exp) in _sessions.items() if exp < now]
    for k in dead_s:
        del _sessions[k]


class RequestCodeBody(BaseModel):
    phone_e164: str = Field(..., description="E.164 or US 10-digit")


class VerifyBody(BaseModel):
    phone_e164: str
    code: str = Field(..., min_length=4, max_length=8)


class ProfileBody(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=80)
    last_name: str = Field(..., min_length=1, max_length=80)
    email: str = Field(..., min_length=3, max_length=200)


@router.post("/auth/request-code")
async def request_code(body: RequestCodeBody) -> dict:
    try:
        phone = _normalize_phone_e164(body.phone_e164)
    except ValueError as e:
        raise HTTPException(status_code=400, detail="Invalid phone number") from e

    fixed = os.getenv("AUTH_OTP_FIXED", "").strip()
    if fixed:
        code = (fixed + "000000")[:6]
    else:
        code = f"{secrets.randbelow(1_000_000):06d}"

    now = time.time()
    async with _lock:
        _purge_expired_unlocked(now)
        _otp_by_phone[phone] = (code, now + OTP_TTL_SEC)

    logger.info("OTP for %s: %s", phone, code)
    return {"ok": True}


@router.post("/auth/verify-code")
async def verify_code(body: VerifyBody) -> dict:
    try:
        phone = _normalize_phone_e164(body.phone_e164)
    except ValueError as e:
        raise HTTPException(status_code=400, detail="Invalid phone number") from e

    code = body.code.strip()
    now = time.time()
    async with _lock:
        _purge_expired_unlocked(now)
        entry = _otp_by_phone.get(phone)
        if not entry:
            raise HTTPException(status_code=400, detail="Code expired or not found; request a new code")
        expected, exp = entry
        if now > exp:
            del _otp_by_phone[phone]
            raise HTTPException(status_code=400, detail="Code expired; request a new code")
        if code != expected:
            raise HTTPException(status_code=400, detail="Invalid code")
        del _otp_by_phone[phone]
        token = "snag_" + secrets.token_urlsafe(32)
        _sessions[token] = (phone, now + SESSION_TTL_SEC)

    return {"access_token": token, "expires_in": int(SESSION_TTL_SEC)}


@router.post("/auth/complete-profile")
async def complete_profile(
    body: ProfileBody,
    authorization: str | None = Header(None),
) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization")
    token = authorization[7:].strip()
    now = time.time()
    async with _lock:
        _purge_expired_unlocked(now)
        pair = _sessions.get(token)
        if not pair:
            raise HTTPException(status_code=401, detail="Invalid or expired session")
        phone, exp = pair
        if now > exp:
            del _sessions[token]
            raise HTTPException(status_code=401, detail="Invalid or expired session")
    logger.info("Profile for %s: %s %s <%s>", phone, body.first_name, body.last_name, body.email)
    return {"ok": True}

"""
Auto-book on Resy via browser automation when a venue becomes available.
Navigates to resy.com venue page, clicks ReservationButton, opts in, and books.
Reports errors to the booking_attempts table for the Error reporter tab.
"""
import logging
import os
import re
from typing import TYPE_CHECKING, Tuple

if TYPE_CHECKING:
    from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# Set RESY_BOOK_HEADLESS=0 or false to open Chrome visibly for debugging
def _is_headless() -> bool:
    v = os.environ.get("RESY_BOOK_HEADLESS", "true").strip().lower()
    return v not in ("0", "false", "no")

RESY_BASE = "https://www.resy.com"
VENUE_URL_TEMPLATE = f"{RESY_BASE}/cities/new-york-ny/venues/{{slug}}?date={{date}}&seats={{seats}}"
RESERVATION_BUTTON_SELECTOR = "[class*='ReservationButton']"
CHECKBOX_TESTID = "order_summary_page-checkbox-venue_opt_in"
BOOK_BUTTON_TESTID = "order_summary_page-button-book"

# Timeouts (ms)
PAGE_LOAD_TIMEOUT = 20_000
CLICK_TIMEOUT = 10_000


def _venue_name_to_slug(venue_name: str) -> str:
    """Convert display name to Resy URL slug: lowercase, spaces to hyphens, drop special chars."""
    if not venue_name or not venue_name.strip():
        return ""
    s = venue_name.strip().lower()
    s = re.sub(r"[''&]", "", s)
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s).strip("-")
    return s or venue_name.strip().lower().replace(" ", "-")


async def run_resy_auto_book(venue_name: str, date_str: str, party_size: int) -> Tuple[bool, str | None]:
    """
    Navigate to Resy venue page and attempt to complete booking flow (async).
    Returns (success, error_message). error_message is None on success.
    """
    slug = _venue_name_to_slug(venue_name)
    if not slug:
        return False, "Invalid venue name (empty slug)."
    url = VENUE_URL_TEMPLATE.format(slug=slug, date=date_str, seats=party_size)

    try:
        from playwright.async_api import async_playwright
    except ImportError:
        return False, "Playwright not installed. Run: pip install playwright && playwright install chromium"

    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=_is_headless())
            try:
                page = await browser.new_page()
                page.set_default_timeout(PAGE_LOAD_TIMEOUT)
                await page.goto(url, wait_until="domcontentloaded")
                await page.wait_for_load_state("networkidle", timeout=PAGE_LOAD_TIMEOUT)

                # Click reservation button (class contains ReservationButton)
                try:
                    btn = page.locator(RESERVATION_BUTTON_SELECTOR).first
                    await btn.wait_for(state="visible", timeout=CLICK_TIMEOUT)
                    await btn.click()
                except Exception as e:
                    return False, f"Could not find or click reservation button (class*='ReservationButton'): {e!s}"

                # Wait for modal; then checkbox
                await page.wait_for_timeout(1500)
                try:
                    checkbox = page.get_by_test_id(CHECKBOX_TESTID)
                    await checkbox.wait_for(state="visible", timeout=CLICK_TIMEOUT)
                    await checkbox.click()
                except Exception as e:
                    if not _is_headless():
                        await page.wait_for_timeout(30_000)  # leave browser open 30s to inspect
                    return False, f"Could not find or click opt-in checkbox (data-testid={CHECKBOX_TESTID!r}): {e!s}"

                # Click book button
                try:
                    book_btn = page.get_by_test_id(BOOK_BUTTON_TESTID)
                    await book_btn.wait_for(state="visible", timeout=CLICK_TIMEOUT)
                    await book_btn.click()
                except Exception as e:
                    if not _is_headless():
                        await page.wait_for_timeout(30_000)
                    return False, f"Could not find or click book button (data-testid={BOOK_BUTTON_TESTID!r}): {e!s}"

                return True, None
            finally:
                await browser.close()
    except Exception as e:
        logger.exception("Resy auto-book failed")
        return False, f"Booking error: {e!s}"


def record_booking_attempt(
    db: "Session",
    venue_name: str,
    date_str: str,
    party_size: int,
    success: bool,
    error_message: str | None,
) -> None:
    """Persist a booking attempt (success or failure) to booking_attempts. Call after run_resy_auto_book."""
    from app.models.booking_attempt import BookingAttempt

    status = "success" if success else "failed"
    row = BookingAttempt(
        venue_name=venue_name,
        date_str=date_str,
        party_size=party_size,
        status=status,
        error_message=error_message,
    )
    db.add(row)
    db.commit()


def run_auto_book_and_record(venue_name: str, date_str: str, party_size: int) -> None:
    """
    Run Resy auto-book and persist the attempt (success or failure) to booking_attempts.
    Safe to call from a background thread; creates its own DB session and runs the async flow.
    """
    import asyncio

    from app.db.session import SessionLocal

    success, error_message = asyncio.run(run_resy_auto_book(venue_name, date_str, party_size))
    db = SessionLocal()
    try:
        record_booking_attempt(db, venue_name, date_str, party_size, success, error_message)
    except Exception as e:
        logger.exception("Failed to save booking attempt")
        db.rollback()
    finally:
        db.close()


def get_recent_booking_attempts(db: "Session", limit: int = 100) -> list[dict]:
    """Return recent booking attempts (for Error reporter tab), newest first."""
    from app.models.booking_attempt import BookingAttempt

    rows = (
        db.query(BookingAttempt)
        .order_by(BookingAttempt.created_at.desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "id": r.id,
            "venue_name": r.venue_name,
            "date_str": r.date_str,
            "party_size": r.party_size,
            "status": r.status,
            "error_message": r.error_message,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]

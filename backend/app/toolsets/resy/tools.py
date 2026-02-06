"""Resy toolset: venue search with availability + check for new venues (diff)."""
from datetime import date
from typing import Any

from pydantic_ai import FunctionToolset, RunContext

from app.agents.deps import ResyDeps
from app.data.infatuation_hard_to_get import get_for_agent as get_infatuation_hard_to_get_service
from app.services.resy import search_with_availability
from app.services.tool_call_log_service import log_tool_call as log_tool_call_service
from app.services.chat_session_service import save_last_venue_search as save_last_venue_search_service
from app.services.venue_snapshot_service import (
    check_for_new_venues as check_for_new_venues_service,
    save_broad_search_snapshot as save_broad_search_snapshot_service,
)
from app.services.venue_notify_service import (
    get_my_watches as get_my_watches_service,
    start_notify_for_all_infatuation as start_notify_for_all_infatuation_service,
    start_venue_notify as start_venue_notify_service,
    update_notify_request_title as update_notify_request_title_service,
)
from app.services.venue_watch_service import get_watch_update as get_watch_update_service
from app.services.venue_watch_service import start_watch as start_watch_service
from app.services.resy_auto_book_service import run_resy_auto_book, record_booking_attempt


def _log_tool(ctx: RunContext[ResyDeps], tool_name: str, **kwargs: Any) -> None:
    """Log tool invocation for the Log tab. Call at the start of each tool."""
    try:
        log_tool_call_service(
            ctx.deps.db,
            tool_name,
            {k: v for k, v in kwargs.items()},
            session_id=ctx.deps.session_id,
        )
    except Exception:
        pass


async def search_venues_with_availability(
    ctx: RunContext[ResyDeps],
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str = "",
    collection_slug: str = "",
    location_code: str = "ny",
) -> dict[str, Any]:
    """Search Resy for restaurants; returns venues with availability. date_str: YYYY-MM-DD. Always pass time_filter when user mentions a time: tonight/dinner/evening -> 19:00 or 20:00, morning -> 09:00, lunch -> 12:00, or explicit e.g. 21:30. API uses ±1h around time_filter."""
    _log_tool(ctx, "search_venues_with_availability", date_str=date_str, party_size=party_size, query=query, time_filter=time_filter, collection_slug=collection_slug, location_code=location_code)
    try:
        day = date.fromisoformat(date_str)
    except ValueError:
        return {"error": f"Invalid date {date_str}. Use YYYY-MM-DD."}
    venue_filter = None
    if (collection_slug or "").strip():
        venue_filter = {"location_code": (location_code or "ny").strip() or "ny", "collection_slug": collection_slug.strip()}
    result = search_with_availability(
        day,
        party_size,
        query=query.strip(),
        time_filter=time_filter.strip() or None,
        venue_filter=venue_filter,
    )
    # Expose to stream and save for sidebar + snapshot/compare (same data).
    if "venues" in result and result.get("venues"):
        venues = result["venues"]
        max_sidebar = 200
        list_for_sidebar = [
            {
                "name": v.get("name") or "",
                "times": v.get("availability_times") or [],
                "image_url": v.get("image_url"),
            }
            for v in (venues[:max_sidebar] if len(venues) > max_sidebar else venues)
        ]
        ctx.deps.last_venue_search = list_for_sidebar
        if ctx.deps.session_id:
            try:
                save_last_venue_search_service(ctx.deps.db, ctx.deps.session_id, list_for_sidebar)
                names = [x.get("name") or "" for x in list_for_sidebar]
                save_broad_search_snapshot_service(
                    ctx.deps.db, date_str, party_size, query or "", (time_filter or "").strip() or None, names
                )
            except Exception:
                pass
    else:
        ctx.deps.last_venue_search = None
    return result


async def check_for_new_venues(
    ctx: RunContext[ResyDeps],
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str = "",
) -> dict[str, Any]:
    """Compare current availability to last check for this date/party_size. Returns {baseline: true, total: N} first time; then {n: new_count, new: [names]} or {n: 0}. Use when user asks to check again in 1–2 min."""
    _log_tool(ctx, "check_for_new_venues", date_str=date_str, party_size=party_size, query=query, time_filter=time_filter)
    return check_for_new_venues_service(
        ctx.deps.db,
        date_str,
        party_size,
        query=query.strip(),
        time_filter=time_filter.strip() or None,
    )


async def start_watch(
    ctx: RunContext[ResyDeps],
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str = "",
    interval_minutes: int = 2,
    venue_names: list[str] | None = None,
) -> dict[str, Any]:
    """Start background watch every N min. Two modes: (1) Specific venues: pass venue_names (list of restaurant names); we query Resy by name per venue and notify when any have availability. (2) New venues: omit venue_names; we run a broad search and notify only when new restaurant names appear vs last run. You MUST pass interval_minutes: 1, 2, 5, or 10. time_filter: 24h e.g. 20:00; checked ±1h. Session required when using venue_names."""
    _log_tool(ctx, "start_watch", date_str=date_str, party_size=party_size, query=query, time_filter=time_filter, interval_minutes=interval_minutes, venue_names=venue_names)
    if venue_names and not ctx.deps.session_id:
        return {"error": "Session required. Start a chat first."}
    return start_watch_service(
        ctx.deps.db,
        date_str,
        party_size,
        query=query.strip(),
        time_filter=time_filter.strip() or None,
        interval_minutes=interval_minutes,
        session_id=ctx.deps.session_id,
        venue_names=venue_names or None,
    )


async def get_watch_update(
    ctx: RunContext[ResyDeps],
    date_str: str,
    party_size: int = 2,
    query: str = "",
    time_filter: str = "",
) -> dict[str, Any]:
    """Get latest result from background watch: {n: 0} or {n: N, new: [names]} or {pending: true}. Use when user asks 'any updates?' or 'any new places?'."""
    _log_tool(ctx, "get_watch_update", date_str=date_str, party_size=party_size, query=query, time_filter=time_filter)
    return get_watch_update_service(
        ctx.deps.db,
        date_str,
        party_size,
        query=query.strip(),
        time_filter=time_filter.strip() or None,
        session_id=ctx.deps.session_id,
    )


async def start_venue_notify(
    ctx: RunContext[ResyDeps],
    venue_name: str,
    date_str: str,
    party_size: int = 2,
    time_filter: str = "",
    title: str = "",
) -> dict[str, Any]:
    """Notify when this venue has availability. Use when user says 'notify me when [venue] is available' or 'tell me when [venue] has a table'. Optional title: user can give a label (e.g. 'Valentine dinner') to identify this notification. Requires session (chat)."""
    _log_tool(ctx, "start_venue_notify", venue_name=venue_name, date_str=date_str, party_size=party_size, time_filter=time_filter, title=title)
    if not ctx.deps.session_id:
        return {"error": "Session required. Start a chat first."}
    return start_venue_notify_service(
        ctx.deps.db,
        ctx.deps.session_id,
        venue_name.strip(),
        date_str,
        party_size,
        time_filter=time_filter.strip() or None,
        title=title.strip() or None,
    )


async def start_notify_for_all_infatuation(
    ctx: RunContext[ResyDeps],
    date_str: str,
    party_size: int = 2,
    time_filter: str = "",
    title_prefix: str = "Infatuation",
) -> dict[str, Any]:
    """Create a notify request for every venue on the Infatuation hard-to-get list. Use when the user says 'notify me for all of them', 'set up notify for the whole list', or 'watch all' (after you have shown the list and they have given date and party size). Requires session. Returns created count and ids. When a venue in the list has resy_venue_id set, matching uses that ID (reliable); otherwise matching is by venue name."""
    _log_tool(ctx, "start_notify_for_all_infatuation", date_str=date_str, party_size=party_size, time_filter=time_filter, title_prefix=title_prefix)
    if not ctx.deps.session_id:
        return {"error": "Session required. Start a chat first."}
    return start_notify_for_all_infatuation_service(
        ctx.deps.db,
        ctx.deps.session_id,
        date_str,
        party_size,
        time_filter=time_filter.strip() or None,
        title_prefix=title_prefix.strip() or None,
    )


async def get_infatuation_hard_to_get(ctx: RunContext[ResyDeps]) -> dict[str, Any]:
    """Return a curated list of NYC restaurants that are among the toughest reservations, from The Infatuation. Use when the user asks for 'hard to get reservations', 'toughest reservations NYC', 'Infatuation best restaurants', or similar. Response includes venues (name, note, list_name), source_label, source_url, and summary. After showing the list, offer to set up Resy notify for any venue(s) they want (use start_venue_notify with the exact name)."""
    _log_tool(ctx, "get_infatuation_hard_to_get")
    return get_infatuation_hard_to_get_service()


async def list_my_watches(ctx: RunContext[ResyDeps]) -> dict[str, Any]:
    """List all active jobs (global): interval watches (check every N min) and notify requests (notify when venue available). Use when you need to find a notify request id (e.g. to update its title) or to describe what they have. Returns notify_requests with id, title, venue_name, date_str, party_size, status."""
    _log_tool(ctx, "list_my_watches")
    return get_my_watches_service(ctx.deps.db)


async def update_venue_notify_title(
    ctx: RunContext[ResyDeps],
    request_id: int,
    title: str,
) -> dict[str, Any]:
    """Update the title of an existing 'notify when venue available' request. Use when the user asks to rename or change the title of a notification (e.g. 'call that one Valentine dinner' or 'change the title to Mom's birthday'). Use list_my_watches first to get notify_requests and find the request_id by venue_name or current title."""
    _log_tool(ctx, "update_venue_notify_title", request_id=request_id, title=title)
    if not ctx.deps.session_id:
        return {"error": "Session required. Start a chat first."}
    return update_notify_request_title_service(ctx.deps.db, request_id, title)


async def book_venue(
    ctx: RunContext[ResyDeps],
    venue_name: str,
    date_str: str,
    party_size: int = 2,
) -> dict[str, Any]:
    """Attempt to book this venue on Resy for the given date and party size. Use when the user says 'book [venue]', 'reserve [venue] for [date] for [N] people', or 'get me a table at [venue]'. Opens Resy, clicks the reservation button, opts in, and confirms. date_str must be YYYY-MM-DD. Returns success or an error message (e.g. button not found, timeout). Booking may take 20–30 seconds."""
    _log_tool(ctx, "book_venue", venue_name=venue_name, date_str=date_str, party_size=party_size)
    venue_name = (venue_name or "").strip()
    if not venue_name:
        return {"error": "venue_name is required."}
    try:
        date.fromisoformat(date_str)
    except ValueError:
        return {"error": f"Invalid date {date_str}. Use YYYY-MM-DD."}
    party_size = max(1, min(party_size, 20))
    success, error_message = await run_resy_auto_book(venue_name, date_str, party_size)
    try:
        record_booking_attempt(
            ctx.deps.db,
            venue_name,
            date_str,
            party_size,
            success,
            error_message,
        )
    except Exception as e:
        return {
            "success": success,
            "error_message": error_message,
            "save_error": str(e),
            "message": "Booking attempt completed but failed to save the result." if success else (error_message or str(e)),
        }
    if success:
        return {"success": True, "message": f"Booked {venue_name} for {date_str} for {party_size}."}
    return {"success": False, "error_message": error_message, "message": error_message or "Booking failed."}


resy_toolset = FunctionToolset(
    tools=[
        search_venues_with_availability,
        check_for_new_venues,
        start_watch,
        get_watch_update,
        get_infatuation_hard_to_get,
        start_venue_notify,
        start_notify_for_all_infatuation,
        list_my_watches,
        update_venue_notify_title,
        book_venue,
    ],
)

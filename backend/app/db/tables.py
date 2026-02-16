"""
Single source of truth for database tables that exist after migrations (023–029).

Use these names when writing raw SQL (e.g. TRUNCATE). Do not reference dropped tables:
  - discovery_scans (024), venue_watches, venue_notify_requests, venue_watch_notifications (025),
  - chat_sessions, watch_list, venue_search_snapshots, booking_attempts, tool_call_logs,
    documents, paystub_insights (026).
"""
# All tables that exist in the DB. Must match models and migrations 023–029.
ALL_TABLE_NAMES = (
    "discovery_buckets",
    "drop_events",
    "venues",
    "feed_cache",
    "venue_metrics",
    "market_metrics",
    "venue_rolling_metrics",
)

# Tables cleared when resetting discovery state (TRUNCATE). Order matters for FK if any.
DISCOVERY_TABLE_NAMES = (
    "drop_events",
    "discovery_buckets",
)

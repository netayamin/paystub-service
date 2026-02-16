"""
Legacy: hourly job stub. The scheduler still runs this every hour but it does nothing.
Discovery (rolling 14-day, buckets + drops) is in discovery_bucket_job.
watch_list table and /resy/watch routes are legacy (not used by the frontend).
"""


def run_hourly_check() -> None:
    pass

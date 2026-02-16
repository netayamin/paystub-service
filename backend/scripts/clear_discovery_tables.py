#!/usr/bin/env python3
"""
Completely clear discovery tables (drop_events, discovery_buckets). Fast (TRUNCATE).
Run with backend stopped to avoid locks: cd backend && poetry run python scripts/clear_discovery_tables.py
"""
import sys
from pathlib import Path

# backend/scripts/ -> backend/
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text

from app.db.session import engine
from app.db.tables import DISCOVERY_TABLE_NAMES


def main():
    tables = ", ".join(DISCOVERY_TABLE_NAMES)
    print(f"Connecting to DB and truncating {tables} ...")
    with engine.connect() as conn:
        conn.execute(text(f"TRUNCATE TABLE {tables} RESTART IDENTITY CASCADE"))
        conn.commit()
    print("Done. Discovery tables are empty. Start the backend; next job run will create fresh buckets.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Drop public schema and run all migrations from scratch.
Use when the DB is in a mixed state (e.g. some tables missing, some leftover) and you want a clean slate.

Run from backend dir:
  poetry run python scripts/drop_schema_and_migrate.py
"""
import subprocess
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from sqlalchemy import text

from app.db.session import engine


def main():
    print("Dropping public schema (all tables)...")
    with engine.connect() as conn:
        conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
        conn.execute(text("CREATE SCHEMA public"))
        conn.execute(text("GRANT ALL ON SCHEMA public TO public"))
        conn.commit()
    print("Schema recreated. Running migrations...")
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=backend_dir,
    )
    if result.returncode != 0:
        sys.exit(result.returncode)
    print("Done. All tables created.")


if __name__ == "__main__":
    main()

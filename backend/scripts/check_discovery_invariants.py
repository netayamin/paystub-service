#!/usr/bin/env python3
"""
Idempotent Postgres checks for discovery / drop_events invariants (Implementation Plan Task 1.5).

Usage (from backend/):
  poetry run python scripts/check_discovery_invariants.py

Exit 0 if all checks pass; exit 1 if any violation (prints reason).
"""
from __future__ import annotations

import sys

from app.services.discovery.invariant_checks import run_discovery_invariant_checks


def main() -> int:
    errs = run_discovery_invariant_checks()
    if errs:
        print("check_discovery_invariants: FAILED")
        for e in errs:
            print(f"  - {e}")
        return 1
    print("check_discovery_invariants: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

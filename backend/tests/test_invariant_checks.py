"""Discovery invariant checks (Task 1.5) — requires Postgres with migrations applied."""
import pytest
from sqlalchemy.exc import OperationalError

from app.services.discovery.invariant_checks import run_discovery_invariant_checks


@pytest.fixture(scope="module")
def db_reachable():
    try:
        errs = run_discovery_invariant_checks()
        return True, errs
    except OperationalError:
        return False, None


def test_discovery_invariants_when_db_available(db_reachable):
    ok, errs = db_reachable
    if not ok:
        pytest.skip("Database not reachable (set DATABASE_URL for integration check)")
    assert errs == [], f"Invariant violations: {errs}"

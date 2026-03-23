"""Unit tests for aggregation helpers (volatility, implied sum_sq)."""
from app.services.aggregation.aggregate import (
    _implied_sum_sq_for_row,
    _volatility_score_from_moments,
)


def test_volatility_none_when_single_sample():
    assert _volatility_score_from_moments(1, 100.0, 10000.0) is None


def test_volatility_increases_with_spread():
    # n=2, mean=100, sum_sq = 50^2+150^2 = 2500+22500 = 25000, var = 12500 - 10000 = 2500, stdev=50, cv=0.5
    low = _volatility_score_from_moments(2, 100.0, 50.0**2 + 150.0**2)
    tight = _volatility_score_from_moments(2, 100.0, 99.0**2 + 101.0**2)
    assert low is not None and tight is not None
    assert low > tight


def test_implied_sum_sq_uses_stored():
    assert _implied_sum_sq_for_row(3, 10.0, 500.0) == 500.0


def test_implied_sum_sq_legacy_proxy():
    assert _implied_sum_sq_for_row(2, 10.0, None) == 200.0

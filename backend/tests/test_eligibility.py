"""Unit tests for discovery eligibility gates and multipliers."""
from app.services.discovery.eligibility import (
    MIN_POLLS_FOR_BASELINE_TRUST,
    push_notification_allowed,
    qualified_for_home_feed,
    rank_strength_multiplier,
    stronger_eligibility_evidence,
)


def test_stronger_eligibility_evidence_ordering():
    assert stronger_eligibility_evidence("unknown", "nonempty_prev_delta") == "nonempty_prev_delta"
    assert stronger_eligibility_evidence("baseline_only", "empty_prev_delta") == "empty_prev_delta"
    assert stronger_eligibility_evidence("nonempty_prev_delta", "unknown") == "nonempty_prev_delta"
    assert stronger_eligibility_evidence(None, None) == "unknown"


def test_qualified_for_home_feed():
    assert qualified_for_home_feed("unknown", 99) is False
    assert qualified_for_home_feed("first_poll_bucket", 99) is False
    assert qualified_for_home_feed("nonempty_prev_delta", 0) is True
    assert qualified_for_home_feed("empty_prev_delta", 0) is True
    assert qualified_for_home_feed("baseline_only", MIN_POLLS_FOR_BASELINE_TRUST - 1) is False
    assert qualified_for_home_feed("baseline_only", MIN_POLLS_FOR_BASELINE_TRUST) is True


def test_rank_strength_multiplier_tiers():
    assert rank_strength_multiplier("nonempty_prev_delta") == 1.0
    assert rank_strength_multiplier("empty_prev_delta") == 0.88
    assert rank_strength_multiplier("baseline_only") == 0.72
    assert rank_strength_multiplier("unknown") == 0.55


def test_push_notification_allowed_stricter_than_feed():
    assert push_notification_allowed("nonempty_prev_delta") is True
    assert push_notification_allowed("empty_prev_delta") is True
    assert push_notification_allowed("baseline_only") is False
    assert push_notification_allowed("unknown") is False

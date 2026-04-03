"""Unit tests for Resy venue state extraction and opportunity scoring helpers."""
from app.services.discovery.opportunity_engine import compute_coverage_score, compute_opportunity_scores_v1
from app.services.resy.venue_state import ABSENT, BOOKABLE, UNBOOKABLE, extract_state_from_hit


def test_extract_absent():
    assert extract_state_from_hit(None) == ABSENT


def test_extract_unbookable_null_availability():
    assert extract_state_from_hit({"name": "X", "availability": None}) == UNBOOKABLE


def test_extract_unbookable_empty_slots():
    assert extract_state_from_hit({"name": "X", "availability": {"slots": []}}) == UNBOOKABLE


def test_extract_bookable():
    hit = {
        "name": "Y",
        "availability": {"slots": [{"date": {"start": "2026-04-01 19:00:00"}}]},
    }
    assert extract_state_from_hit(hit) == BOOKABLE


def test_coverage_nonempty():
    assert compute_coverage_score(50, 0) >= 0.8


def test_coverage_errors():
    assert compute_coverage_score(50, 10) < 0.8


def test_opportunity_score_keys():
    s = compute_opportunity_scores_v1(
        "STRONG_OPEN",
        None,
        0.9,
        2,
        "20:00",
    )
    assert "opportunity_score" in s
    assert s["opportunity_score"] >= 0

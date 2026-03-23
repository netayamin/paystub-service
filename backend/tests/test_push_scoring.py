"""Unit tests for push delivery ordering heuristics (Phase 7.3)."""
from app.services.discovery.push_scoring import (
    push_delivery_score,
    should_use_rare_opening_title,
)


def _hot(_: str | None) -> bool:
    return False


def _hot_carbone(name: str | None) -> bool:
    return (name or "").lower().find("carbone") >= 0


def test_saved_venue_gets_higher_score_than_anonymous_hotspot_only():
    rarity = {"vid1": 50.0}
    s_saved = push_delivery_score(
        "don angie",
        "Don Angie",
        "vid1",
        "nonempty_prev_delta",
        explicit_includes={"don angie"},
        rarity_by_venue_id=rarity,
        is_hotspot_fn=_hot,
    )
    s_not_saved = push_delivery_score(
        "don angie",
        "Don Angie",
        "vid1",
        "nonempty_prev_delta",
        explicit_includes=set(),
        rarity_by_venue_id=rarity,
        is_hotspot_fn=_hot,
    )
    assert s_saved > s_not_saved


def test_rarity_increases_score_when_venue_id_present():
    base = push_delivery_score(
        "x",
        "X",
        "v1",
        "empty_prev_delta",
        explicit_includes=set(),
        rarity_by_venue_id={"v1": 0.0},
        is_hotspot_fn=_hot,
    )
    high = push_delivery_score(
        "x",
        "X",
        "v1",
        "empty_prev_delta",
        explicit_includes=set(),
        rarity_by_venue_id={"v1": 100.0},
        is_hotspot_fn=_hot,
    )
    assert high > base


def test_rare_title_high_rarity():
    assert should_use_rare_opening_title(
        "foo",
        "Foo",
        "v1",
        explicit_includes=set(),
        rarity_by_venue_id={"v1": 80.0},
        is_hotspot_fn=_hot,
    )


def test_rare_title_saved_hotspot_moderate_rarity():
    assert should_use_rare_opening_title(
        "carbone",
        "Carbone",
        "v2",
        explicit_includes={"carbone"},
        rarity_by_venue_id={"v2": 50.0},
        is_hotspot_fn=_hot_carbone,
    )

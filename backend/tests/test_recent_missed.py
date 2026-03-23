"""Unit tests for just_missed vs current availability keys."""
from app.services.discovery.recent_missed import (
    collect_bookable_venue_keys,
    venue_identity_key,
)


def test_venue_identity_key_prefers_id():
    assert venue_identity_key("RESY-123", "Some Place") == "resy-123"


def test_venue_identity_key_falls_back_to_name():
    assert venue_identity_key(None, "Carbone") == "carbone"
    assert venue_identity_key("", "Carbone") == "carbone"


def test_collect_bookable_venue_keys_unions_jo_and_so():
    jo = [{"venues": [{"venue_id": "a", "name": "A"}, {"name": "Only Name"}]}]
    so = [{"venues": [{"venue_id": "b", "name": "B"}]}]
    keys = collect_bookable_venue_keys(jo, so)
    assert keys == {"a", "only name", "b"}

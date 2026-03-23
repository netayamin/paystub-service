"""Feed builder: weak just-opened-only cards excluded; still_open keeps venue."""
from app.services.discovery.feed import build_feed


def _venue(
    name: str,
    *,
    evidence: str | None = None,
    polls: int | None = None,
    times: list | None = None,
):
    v = {
        "name": name,
        "venue_id": "v1",
        "neighborhood": "SoHo",
        "availability_times": times or ["2025-03-21 19:00:00"],
        "resy_url": "https://resy.com/foo",
    }
    if evidence is not None:
        v["eligibility_evidence"] = evidence
    if polls is not None:
        v["bucket_successful_poll_count"] = polls
    return v


def test_build_feed_drops_unqualified_just_opened_only():
    jo = [{"date_str": "2025-03-21", "venues": [_venue("Weak Spot", evidence="unknown", polls=5)]}]
    out = build_feed(jo, [])
    assert out["ranked_board"] == []


def test_build_feed_keeps_diff_backed_just_opened():
    jo = [
        {
            "date_str": "2025-03-21",
            "venues": [_venue("Strong Spot", evidence="nonempty_prev_delta", polls=0)],
        }
    ]
    out = build_feed(jo, [])
    assert len(out["ranked_board"]) == 1
    assert out["ranked_board"][0]["name"] == "Strong Spot"


def test_build_feed_keeps_unqualified_just_opened_when_still_open_present():
    name = "Mixed Spot"
    jo = [{"date_str": "2025-03-21", "venues": [_venue(name, evidence="unknown", polls=5)]}]
    so = [{"date_str": "2025-03-21", "venues": [_venue(name, evidence="unknown", polls=5)]}]
    out = build_feed(jo, so)
    assert len(out["ranked_board"]) == 1
    assert out["ranked_board"][0]["name"] == name

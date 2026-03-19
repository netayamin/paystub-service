"""
Market-aware hotspot (hotlist) venues: hard-to-get restaurants we treat as special for notifications and ranking.

- NYC: Alex Reichek top list + Resy classics.
- Miami: Curated Miami Beach & Miami popular / tough-to-get spots.
Match by normalized venue name (case-insensitive); substring match for display names.
"""
from __future__ import annotations

import re
import unicodedata

# ---------------------------------------------------------------------------
# NYC (same as legacy nyc_hotspots)
# ---------------------------------------------------------------------------
NYC_HOTSPOT_NAMES = sorted({
    "Theodora", "The Corner Store", "Zou Zou", "Thai Diner", "Lilia", "Russ & Daughters",
    "Ha's Snack Bar", "Via Carota", "Rule of Thirds", "Coqodaq", "Ippudo", "Di An Di",
    "Leo", "Balthazar", "Laser Wolf", "Gupshup", "Planta Queen", "Bangkok Supper Club",
    "Nami Nori", "Margot", "Mokbar", "Saigon Social", "Blue Ribbon Sushi", "L'Industrie",
    "Shuka", "Pastis", "Minetta Tavern", "Don Angie", "Cafe Spaghetti", "Chez Ma Tante",
    "Misi", "Twin Tails", "Dame", "Babbo", "Wu's Wonton", "Miss Ada",
    "Carbone", "Cote", "Le Bernardin", "I Sodi", "Tatiana", "Atomix",
    "4 Charles Prime Rib", "Eleven Madison Park", "Per Se",
})

# Top-priority names for "Top Drops" — the absolute hardest to get in NYC.
# Ordered by prestige / scarcity. Matched as substrings (case-insensitive).
NYC_TOP_OPPORTUNITY_PRIORITY = (
    "don angie", "lilia", "i sodi", "via carota", "tatiana",
    "carbone", "le bernardin", "atomix", "four charles", "4 charles",
    "eleven madison", "per se", "minetta tavern", "cote", "babbo",
    "laser wolf", "coqodaq", "rule of thirds", "chez ma tante", "misi",
    "cafe spaghetti", "gupshup", "balthazar", "pastis", "dame",
)

# ---------------------------------------------------------------------------
# Miami Beach & Miami: popular / tough-to-get spots
# ---------------------------------------------------------------------------
MIAMI_HOTSPOT_NAMES = sorted({
    "Carbone Miami",
    "Hiden",
    "L'Atelier de Joël Robuchon",
    "NAOE",
    "Stubborn Seed",
    "Katsuya",
    "Zuma",
    "Komodo",
    "Papi Steak",
    "Cote Miami",
    "Swan",
    "Mandolin Aegean Bistro",
    "Michael's Genuine",
    "Upland",
    "Marino's",
    "Barton G",
    "Prime 112",
    "Joe's Stone Crab",
    "Nobu Miami",
    "Hakkasan",
    "Cecconi's",
    "Quattro",
    "La Mar",
    "LPM",
    "Sushi by Bou",
    "The Forge",
    "Kiki on the River",
    "Casa Tua",
    "The Bazaar",
    "Leku",
    "Gekko",
    "Doya",
    "Dolphin Mall",
    "Serendipity",
})

# Top-priority for Miami "Top Opportunities"
MIAMI_TOP_OPPORTUNITY_PRIORITY = ("carbone miami", "hiden", "cote miami", "stubborn seed", "naoe")


def _normalize(s: str) -> str:
    if not s or not isinstance(s, str):
        return ""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = s.lower().strip()
    s = re.sub(r"\s+", " ", s)
    return s


def _normalized_set(names: set[str]) -> set[str]:
    return {_normalize(n) for n in names}


_NYC_NORM = _normalized_set(set(NYC_HOTSPOT_NAMES))
_MIAMI_NORM = _normalized_set(set(MIAMI_HOTSPOT_NAMES))


def _is_hotspot_for_set(venue_name: str | None, normalized_set: set[str]) -> bool:
    if not venue_name or not normalized_set:
        return False
    n = _normalize(venue_name)
    if n in normalized_set:
        return True
    for h in normalized_set:
        if h in n or n in h:
            return True
    return False


def list_hotspots(market: str = "nyc") -> list[str]:
    """Return sorted list of canonical hotspot names for the given market."""
    if (market or "").strip().lower() == "miami":
        return list(MIAMI_HOTSPOT_NAMES)
    return list(NYC_HOTSPOT_NAMES)


def is_hotspot(venue_name: str | None, market: str = "nyc") -> bool:
    """True if venue_name is in the hotspot list for the given market."""
    if (market or "").strip().lower() == "miami":
        return _is_hotspot_for_set(venue_name, _MIAMI_NORM)
    return _is_hotspot_for_set(venue_name, _NYC_NORM)


def top_priority_names(market: str = "nyc") -> tuple[str, ...]:
    """Names that get a slot in Top Opportunities when present (for feed ranking)."""
    if (market or "").strip().lower() == "miami":
        return MIAMI_TOP_OPPORTUNITY_PRIORITY
    return NYC_TOP_OPPORTUNITY_PRIORITY

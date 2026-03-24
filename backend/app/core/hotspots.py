"""
Market-aware hotspot (hotlist) venues: hard-to-get restaurants we treat as special for notifications and ranking.

- NYC: ~200 of NYC's most desirable / hardest-to-book restaurants across all neighborhoods.
- Miami: Curated Miami Beach & Miami popular / tough-to-get spots.
Match by normalized venue name (case-insensitive); substring match for display names.
"""
from __future__ import annotations

import re
import unicodedata

# ---------------------------------------------------------------------------
# NYC — ~200 of the city's most desirable / hardest-to-book restaurants
# ---------------------------------------------------------------------------
NYC_HOTSPOT_NAMES = sorted({
    # ── Original core list ──────────────────────────────────────────────────
    "Theodora", "The Corner Store", "Zou Zou", "Thai Diner", "Lilia", "Russ & Daughters",
    "Ha's Snack Bar", "Via Carota", "Rule of Thirds", "Coqodaq", "Ippudo", "Di An Di",
    "Leo", "Balthazar", "Laser Wolf", "Gupshup", "Planta Queen", "Bangkok Supper Club",
    "Nami Nori", "Margot", "Mokbar", "Saigon Social", "Blue Ribbon Sushi", "L'Industrie",
    "Shuka", "Pastis", "Minetta Tavern", "Don Angie", "Cafe Spaghetti", "Chez Ma Tante",
    "Misi", "Twin Tails", "Dame", "Babbo", "Wu's Wonton", "Miss Ada",
    "Carbone", "Cote", "Le Bernardin", "I Sodi", "Tatiana", "Atomix",
    "4 Charles Prime Rib", "Eleven Madison Park", "Per Se",

    # ── Fine dining & Michelin ───────────────────────────────────────────────
    "Daniel", "Jean-Georges", "Gabriel Kreuther", "Aquavit", "Le Coucou",
    "The Modern", "Gramercy Tavern", "Union Square Cafe", "Craft", "Aureole",
    "Ai Fiori", "Marea", "Casa Mono", "Tocqueville", "Blue Hill",
    "Aldea", "Dovetail", "Atera", "Blanca", "Chef's Table at Brooklyn Fare",
    "Masa", "Sushi Nakazawa", "Sushi Yasuda", "15 East", "Kappo Masa",
    "Sushi Ginza Onodera", "Sushi Amane", "Shuko", "Neta", "Jewel Bako",
    "Kajitsu", "Kyo Ya", "Soto", "En Japanese Brasserie",
    "Crown Shy", "Manhatta", "Eleven Madison Park",

    # ── Italian & pasta-focused ──────────────────────────────────────────────
    "L'Artusi", "Perla", "Café Altro Paradiso", "Vic's", "Il Buco",
    "Il Buco Alimentari", "Locanda Verde", "Bar Primi", "Maialino",
    "Sant Ambroeus", "Scarpetta", "Peasant", "Raoul's", "Frankies 457",
    "Prime Meats", "Roman's", "Lupa", "Osteria Morini", "Noodle Pudding",

    # ── French ──────────────────────────────────────────────────────────────
    "Buvette", "Bar Boulud", "Boulud Sud", "Café Boulud", "db Bistro Moderne",
    "Frenchette", "Dirty French", "Le Crocodile", "Benoit",
    "Lucien", "Tartine", "Bar Marseille",

    # ── Steak & American ────────────────────────────────────────────────────
    "Peter Luger", "Keens Steakhouse", "Wolfgang's Steakhouse", "Sparks Steakhouse",
    "Porter House Bar and Grill", "Quality Meats", "The Grill", "The Pool",
    "Crown Shy", "St. Anselm", "M. Wells Steakhouse", "Marlow Bistro",

    # ── Seafood ─────────────────────────────────────────────────────────────
    "Lure Fishbar", "Flex Mussels", "Greenpoint Fish & Lobster", "Neptune Oyster",
    "Blue Ribbon Brasserie", "Grand Banks", "Cull & Pistol",

    # ── Modern American / New American ──────────────────────────────────────
    "Estela", "Charlie Bird", "Prune", "Hearth", "Upland",
    "Jack's Wife Freda", "Casa Lever", "The NoMad", "Olmsted",
    "Sunday in Brooklyn", "Francie", "Aska", "Oxalis", "Faro",
    "The Four Horsemen", "Maison Premiere", "Achilles Heel",
    "Vinegar Hill House", "Colonie", "Walter's", "Popina",
    "Bar Corvo", "Sauvage", "Celestine", "Stevie", "Bar Pisellino",
    "Emmett's", "Rucola", "Loulou",

    # ── Asian ───────────────────────────────────────────────────────────────
    "Nobu", "Nobu Downtown", "Cosme", "Oxomoco", "Llama Inn", "Llama San",
    "Casa Enrique", "Oxalis", "Mu Ramen", "Ivan Ramen", "Totto Ramen",
    "Hide-Chan Ramen", "Momofuku Ko", "Momofuku Noodle Bar", "Momofuku Ssäm Bar",
    "Nakamura", "Ichiran", "Okonomi", "Ki Sushi", "Tanoshi Sushi",
    "Cafe China", "Hutong", "Hao Noodle", "RedFarm", "Decoy",
    "Jeepney", "Pig & Khao", "Fish Cheeks", "Ugly Baby", "Somtum Der",
    "Wayla", "Ugly Baby", "Khe-Yo", "Hanoi House", "Nam Son",

    # ── Pizza ────────────────────────────────────────────────────────────────
    "Roberta's", "Emily", "Lucali", "Una Pizza Napoletana", "Kesté",
    "Paulie Gee's", "Ops", "Speedy Romeo", "Motorino", "Rubirosa",
    "Corner Slice", "Barboncino", "San Matteo",

    # ── Wine bars & casual fine ──────────────────────────────────────────────
    "Wildair", "Ten Bells", "Compagnie des Vins Surnaturels", "Pijiu Belly",
    "June Wine Bar", "Chambers Street Wines", "Tertulia",

    # ── Brunch / all-day ────────────────────────────────────────────────────
    "Russ & Daughters Cafe", "Egg Shop", "Dimes", "Rosemary's",
    "Cookshop", "Buttermilk Channel", "Marlow & Sons",

    # ── Latino / Caribbean ───────────────────────────────────────────────────
    "Cosme", "Atla", "La Contenta", "Calle Dao", "Malecon",
    "Amor Cubano", "La Loncheria", "Lupe",

    # ── Middle Eastern & Mediterranean ──────────────────────────────────────
    "Bavel", "Nur", "Gazala's", "Nish Nush", "Au Za'atar", "Dagon",
    "Lilia" , "Zaytinya",

    # ── Bars with great food ─────────────────────────────────────────────────
    "Employees Only", "Attaboy", "Death & Co", "Please Don't Tell",
    "Amor y Amargo", "Cienfuegos",
})

# Top-priority names for "Top Drops" — the absolute hardest to get in NYC.
# Ordered by prestige / demand. Matched as substrings (case-insensitive).
NYC_TOP_OPPORTUNITY_PRIORITY = (
    "don angie", "lilia", "i sodi", "via carota", "tatiana",
    "carbone", "le bernardin", "atomix", "four charles", "4 charles",
    "eleven madison", "per se", "minetta tavern", "cote", "babbo",
    "laser wolf", "coqodaq", "rule of thirds", "chez ma tante", "misi",
    "cafe spaghetti", "gupshup", "balthazar", "pastis", "dame",
    "sushi nakazawa", "masa", "chef's table", "blanca", "atera",
    "gabriel kreuther", "le coucou", "crown shy", "estela", "frenchette",
    "gramercy tavern", "daniel", "jean-georges", "cosme", "olmsted",
    "aska", "francie", "maison premiere", "the four horsemen",
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
        # "carbone" in "carbone nyc" → True (hotspot name is a word-boundary prefix of venue)
        # Guard: only allow substring match when the hotspot name is long enough (≥5 chars)
        # to avoid short names like "leo" matching "galileo", "napoleon's", etc.
        if len(h) >= 5 and h in n:
            return True
        # Also allow venue name to match as a prefix of the hotspot name, but only
        # when the hotspot name has a space suffix (e.g. "misi " in "misi - new york").
        # We check word-boundary containment to avoid "bar" matching "barton g".
        if len(n) >= 5 and n in h:
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

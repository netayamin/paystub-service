"""
Market-aware hotspot (hotlist) venues for ranking and notifications.
Match is case-insensitive substring (normalized). Add/remove names here to tune the feed.
"""
from __future__ import annotations

import re
import unicodedata

NYC_HOTSPOT_NAMES = sorted({
    "4 Charles Prime Rib", "15 East", "Achilles Heel", "Agern", "Ai Fiori",
    "Aldea", "Alma", "Amor Cubano", "Aquavit", "Aska", "Atla", "Atomix",
    "Atera", "Attaboy", "Au Za'atar", "Aureole", "Babbo", "Bangkok Supper Club",
    "Barboncino", "Bar Boulud", "Bar Corvo", "Bar Marseille", "Bar Pisellino",
    "Bar Primi", "Balthazar", "Bavel", "Benoit", "Blanca", "Blue Hill",
    "Blue Ribbon Brasserie", "Blue Ribbon Sushi", "Boulud Sud",
    "Buttermilk Channel", "Buvette", "Café Altro Paradiso", "Café Boulud",
    "Cafe China", "Cafe Spaghetti", "Carbone", "Casa Enrique", "Casa Lever",
    "Casa Mono", "Celestine", "Charlie Bird", "Chef's Table at Brooklyn Fare",
    "Chez Ma Tante", "Colonie", "Compagnie des Vins Surnaturels", "Cookshop",
    "Corner Slice", "Cosme", "Cote", "Craft", "Crown Shy", "Cull & Pistol",
    "Dame", "Daniel", "db Bistro Moderne", "Death & Co", "Decoy", "Di An Di",
    "Dimes", "Dirty French", "Don Angie", "Dovetail", "Egg Shop",
    "Emily", "Emmett's", "Employees Only", "En Japanese Brasserie",
    "Estela", "Faro", "Fish Cheeks", "Flex Mussels", "Frankies 457",
    "Francie", "Frenchette", "Gabriel Kreuther", "Grand Banks", "Gramercy Tavern",
    "Greenpoint Fish & Lobster", "Gupshup", "Ha's Snack Bar", "Hanoi House",
    "Hao Noodle", "Hearth", "Hide-Chan Ramen", "Hutong", "I Sodi",
    "Ichiran", "Il Buco", "Il Buco Alimentari", "Ippudo", "Ivan Ramen",
    "Jack's Wife Freda", "Jean-Georges", "Jeepney", "Jewel Bako",
    "June Wine Bar", "Kajitsu", "Kappo Masa", "Keens Steakhouse",
    "Kesté", "Khe-Yo", "Ki Sushi", "Kyo Ya", "L'Artusi", "L'Industrie",
    "La Contenta", "Laser Wolf", "Le Bernardin", "Le Coucou", "Le Crocodile",
    "Leo", "Lilia", "Llama Inn", "Llama San", "Locanda Verde", "Loulou",
    "Lucali", "Lucien", "Lupa", "Lure Fishbar", "Maialino", "Maison Premiere",
    "Manhatta", "Marea", "Margot", "Marlow & Sons", "Masa", "Minetta Tavern",
    "Misi", "Miss Ada", "Mokbar", "Momofuku Ko", "Momofuku Noodle Bar",
    "Momofuku Ssäm Bar", "Motorino", "Mu Ramen", "Nakamura", "Nami Nori",
    "Neptune Oyster", "Neta", "Nobu", "Nobu Downtown", "Noodle Pudding",
    "Nur", "Okonomi", "Olmsted", "Ops", "Osteria Morini", "Oxalis",
    "Oxomoco", "Paulie Gee's", "Peasant", "Per Se", "Perla",
    "Peter Luger", "Pig & Khao", "Planta Queen", "Popina", "Porter House Bar and Grill",
    "Prime Meats", "Prune", "Quality Meats", "Raoul's", "RedFarm",
    "Roberta's", "Roman's", "Rosemary's", "Rucola", "Rule of Thirds",
    "Rubirosa", "Russ & Daughters", "Russ & Daughters Cafe", "Saigon Social",
    "Sant Ambroeus", "Sauvage", "Scarpetta", "Shuka", "Shuko",
    "Somtum Der", "Soto", "Sparks Steakhouse", "Speedy Romeo", "St. Anselm",
    "Stevie", "Sunday in Brooklyn", "Sushi Amane", "Sushi Ginza Onodera",
    "Sushi Nakazawa", "Sushi Yasuda", "Tanoshi Sushi", "Tatiana", "Ten Bells",
    "Tertulia", "Thai Diner", "The Corner Store", "The Four Horsemen",
    "The Grill", "The Modern", "The NoMad", "The Pool", "Theodora",
    "Tocqueville", "Totto Ramen", "Twin Tails", "Ugly Baby", "Una Pizza Napoletana",
    "Union Square Cafe", "Upland", "Vic's", "Via Carota", "Vinegar Hill House",
    "Walter's", "Wayla", "Wildair", "Wolfgang's Steakhouse", "Wu's Wonton",
    "Zaytinya", "Zou Zou",
})

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

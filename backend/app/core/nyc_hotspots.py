"""
NYC hotspot venues: hard-to-get restaurants we treat as special for notifications.
Source: https://alexreichek.com/top-nyc-restaurants/ (curated ~40) + a few Resy toughest classics.
Match by normalized venue name (case-insensitive, collapsed spaces); substring match so "Planta Queen" matches "PLANTA Queen, NoMad".
"""
import re
import unicodedata

# Curated top NYC restaurants (Alex Reichek list + Carbone, Cote, Le Bernardin, etc. for Resy matching). One canonical name per line.
NYC_HOTSPOT_NAMES = """
Theodora
The Corner Store
Zou Zou
Thai Diner
Lilia
Russ & Daughters
Ha's Snack Bar
Via Carota
Rule of Thirds
Coqodaq
Ippudo
Di An Di
Leo
Balthazar
Laser Wolf
Gupshup
Planta Queen
Bangkok Supper Club
Nami Nori
Margot
Mokbar
Saigon Social
Blue Ribbon Sushi
L'Industrie
Shuka
Pastis
Minetta Tavern
Don Angie
Cafe Spaghetti
Chez Ma Tante
Misi
Twin Tails
Dame
Babbo
Wu's Wonton
Miss Ada
Carbone
Cote
Le Bernardin
I Sodi
Tatiana
Atomix
4 Charles Prime Rib
Eleven Madison Park
Per Se
""".strip().splitlines()

# Dedupe and clean
NYC_HOTSPOT_NAMES = sorted({n.strip() for n in NYC_HOTSPOT_NAMES if n.strip()})


def _normalize(s: str) -> str:
    if not s or not isinstance(s, str):
        return ""
    # NFD and strip accents for "Café" -> "Cafe"
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = s.lower().strip()
    s = re.sub(r"\s+", " ", s)
    return s


# Precompute normalized set for fast lookup
_NORMALIZED_HOTSPOTS = {_normalize(n) for n in NYC_HOTSPOT_NAMES}


def is_hotspot(venue_name: str | None) -> bool:
    """True if venue_name (or its normalized form) is in the NYC hotspot list."""
    if not venue_name:
        return False
    n = _normalize(venue_name)
    if n in _NORMALIZED_HOTSPOTS:
        return True
    # Substring match so "Tatiana" matches "Tatiana by Kwame Onwuachi", "Planta Queen" matches "PLANTA Queen, NoMad"
    for h in _NORMALIZED_HOTSPOTS:
        if h in n or n in h:
            return True
    return False


def list_hotspots() -> list[str]:
    """Return sorted list of canonical hotspot names (for admin/debug)."""
    return list(NYC_HOTSPOT_NAMES)

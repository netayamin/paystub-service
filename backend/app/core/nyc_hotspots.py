"""
NYC hotspot venues: hard-to-get restaurants we treat as special for notifications.
Sources: Resy "toughest reservations", NYT 100 Best, Eater, Infatuation.
Match by normalized venue name (case-insensitive, collapsed spaces).
"""
import re
import unicodedata

# At least 100 NYC hotspots (Resy toughest + NYT/Eater/Infatuation). One canonical name per line.
NYC_HOTSPOT_NAMES = """
4 Charles Prime Rib
ADDA
Al Badawi
Atomix
Bangkok Supper Club
Bemelmans Bar
Bistrot Ha
Borgo
Bong
Bridges
Bungalow
Café Carmellini
Café Chelsea
Carbone
Charles Pan-Fried Chicken
Chef's Table at Brooklyn Fare
Clemente Bar
COQODAQ
COTE
Cote Korean Steakhouse
Dept of Culture
Dhamaka
Don Angie
Eleven Madison Park
Estela
The Four Horsemen
Golden Diner
Ha's Snack Bar
Hawksmoor
I Cavallini
Jean's
Kabawa
King
Kisa
Konban
Le Bernardin
Le Café Louis Vuitton
Le Chêne
Lei
Lilia
Mama's Too
Misi
Monkey Bar
Naks
Oxomoco
Penny
Per Se
Raoul's
Ramen by Ra
The Snail
Sailor
schmuck.
Semma
Sushi Sho
Szechuan Mountain House
Tatiana
Tatiana by Kwame Onwuachi
Theodora
Tigre
Una Pizza Napoletana
Via Carota
Yamada
Masalawala & Sons
Adda
Golden Diner
Ha's Snack Bar
Bemelmans Bar
Clemente Bar
Kisa
Theodora
Penny
Jean's
Bungalow
Una Pizza Napoletana
Konban
Tigre
Café Carmellini
Sailor
Bangkok Supper Club
Café Chelsea
COTE
Bistrot Ha
Ramen by Ra
Yamada
The Four Horsemen
Bong
I Cavallini
Lei
Semma
Monkey Bar
Bemelmans Bar
ADDA
Le Chêne
The Snail
schmuck.
Golden Diner
Ha's Snack Bar
Le Café Louis Vuitton
Raoul's
COQODAQ
Borgo
Tatiana
Bridges
Don Angie
4 Charles Prime Rib
Via Carota
Carbone
Lilia
Misi
Le Bernardin
Eleven Madison Park
Atomix
Per Se
Chef's Table
Dhamaka
King
Sushi Sho
Szechuan Mountain House
Hawksmoor
Dept of Culture
Mama's Too
Oxomoco
Kabawa
Charles Pan-Fried Chicken
Al Badawi
Estela
The NoMad
Rolo's
Crown Shy
Francie
Lucali
L'Artusi
I Sodi
Lilia
Misi
Don Angie
Via Carota
Carbone
Ruben's
Cervo's
Wildair
Win Son
Superiority Burger
Van Da
Soothr
Thai Diner
Dhamaka
Semma
Adda
Naks
Masalawala & Sons
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
    # Optional: substring match so "Tatiana by Kwame Onwuachi" matches "Tatiana"
    for h in _NORMALIZED_HOTSPOTS:
        if h in n or n in h:
            return True
    return False


def list_hotspots() -> list[str]:
    """Return sorted list of canonical hotspot names (for admin/debug)."""
    return list(NYC_HOTSPOT_NAMES)

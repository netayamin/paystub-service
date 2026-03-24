"""
NYC hotspot venues for ranking and notifications.
Add or remove names here to tune the feed. Matching is case-insensitive
and accent-insensitive (café == cafe), with substring fallback for
venue names that include suffixes like "Carbone NYC".
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

# Pre-computed normalised set for O(1) lookup
def _norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", s.lower().strip())

_NYC_NORM = {_norm(n) for n in NYC_HOTSPOT_NAMES}


def is_hotspot(venue_name: str | None, market: str = "nyc") -> bool:
    if not venue_name:
        return False
    n = _norm(venue_name)
    if n in _NYC_NORM:
        return True
    # Substring match: "Carbone NYC" → matches "carbone" (min 5 chars to avoid false positives)
    return any((len(h) >= 5 and h in n) or (len(n) >= 5 and n in h) for h in _NYC_NORM)


def list_hotspots(market: str = "nyc") -> list[str]:
    return list(NYC_HOTSPOT_NAMES)


def top_priority_names(market: str = "nyc") -> tuple[str, ...]:
    return NYC_TOP_OPPORTUNITY_PRIORITY

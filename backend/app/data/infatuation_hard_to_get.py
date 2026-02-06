"""
Hard-to-get NYC restaurants curated from The Infatuation’s NYC guides.

Use for: “toughest reservations”, “hard to get”, “Infatuation best”, etc.
Names should match Resy display names so notify-by-venue works.
Source: https://www.theinfatuation.com/new-york
"""
from typing import TypedDict


class HardToGetVenue(TypedDict, total=False):
    name: str  # Resy display name (for notify matching)
    note: str  # Short blurb (cuisine / why it’s tough)
    list_name: str  # e.g. "Toughest Reservations", "Hit List"
    resy_venue_id: int  # Optional Resy venue ID for reliable matching; add when you have it


# Sourced only from The Infatuation's NYC guides (as of Jan 2026).
# Toughest Reservations: https://www.theinfatuation.com/new-york/guides/toughest-restaurant-reservations-nyc
# Hit List: https://www.theinfatuation.com/new-york/guides/best-new-new-york-restaurants-hit-list
# Names match Infatuation article titles; Resy may use slightly different names (e.g. "Torrisi" vs "Torrisi Bar & Restaurant").
# To get reliable notify matching, add resy_venue_id to any entry (from Resy search/API). Example: {"name": "Carbone", "note": "...", "list_name": "...", "resy_venue_id": 12345}
INFATUATION_HARD_TO_GET: list[HardToGetVenue] = [
    # Toughest Reservations In NYC Right Now (And How To Get Them)
    {"name": "Bistrot Ha", "note": "French/Vietnamese, Lower East Side", "list_name": "Toughest Reservations"},
    {"name": "Ramen By Ra", "note": "Ramen, East Village", "list_name": "Toughest Reservations"},
    {"name": "Sushi Sho", "note": "Omakase, Midtown", "list_name": "Toughest Reservations"},
    {"name": "Semma", "note": "South Indian, West Village", "list_name": "Toughest Reservations"},
    {"name": "The Eighty Six", "note": "Steakhouse, West Village", "list_name": "Toughest Reservations"},
    {"name": "Wild Cherry", "note": "American, West Village", "list_name": "Toughest Reservations"},
    {"name": "Musaafer", "note": "Indian, Tribeca", "list_name": "Toughest Reservations"},
    {"name": "Bong", "note": "Cambodian, Crown Heights", "list_name": "Toughest Reservations"},
    {"name": "I Cavallini", "note": "Italian, Williamsburg", "list_name": "Toughest Reservations"},
    {"name": "Una Pizza Napoletana", "note": "Pizza, Lower East Side", "list_name": "Toughest Reservations"},
    {"name": "Red Hook Tavern", "note": "American, Red Hook", "list_name": "Toughest Reservations"},
    {"name": "Ha's Snack Bar", "note": "Wine bar / Vietnamese-inspired, Lower East Side", "list_name": "Toughest Reservations"},
    {"name": "The Corner Store", "note": "American, SoHo", "list_name": "Toughest Reservations"},
    {"name": "Le Veau d'Or", "note": "French, Upper East Side", "list_name": "Toughest Reservations"},
    {"name": "The Polo Bar", "note": "American, Midtown East", "list_name": "Toughest Reservations"},
    {"name": "The Four Horsemen", "note": "Wine bar, Williamsburg", "list_name": "Toughest Reservations"},
    {"name": "Tatiana", "note": "Pan-African, Lincoln Center", "list_name": "Toughest Reservations"},
    {"name": "Torrisi Bar & Restaurant", "note": "Italian, Nolita", "list_name": "Toughest Reservations"},
    {"name": "Carbone", "note": "Italian, Greenwich Village", "list_name": "Toughest Reservations"},
    {"name": "Atomix", "note": "Korean tasting menu, NoMad", "list_name": "Toughest Reservations"},
    {"name": "4 Charles Prime Rib", "note": "American steakhouse, West Village", "list_name": "Toughest Reservations"},
    {"name": "Rao's", "note": "Italian, East Harlem (standing tables only)", "list_name": "Toughest Reservations"},
    # The Hit List: New NYC Restaurants To Try Right Now
    {"name": "The History", "note": "Georgian, Hell's Kitchen", "list_name": "Hit List"},
    {"name": "Diljān", "note": "Bakery/cafe, Brooklyn Heights", "list_name": "Hit List"},
    {"name": "Vato", "note": "Mexican tortilleria, Park Slope", "list_name": "Hit List"},
    {"name": "Barker Cafeteria", "note": "Bakery/cafe, Bed-Stuy", "list_name": "Hit List"},
    {"name": "Il Leone", "note": "Pizza, Park Slope", "list_name": "Hit List"},
    {"name": "Falansai", "note": "Vietnamese, Greenpoint", "list_name": "Hit List"},
    {"name": "Danny's", "note": "American, Flatiron", "list_name": "Hit List"},
    {"name": "Salvo's", "note": "Sandwiches, Ridgewood", "list_name": "Hit List"},
    {"name": "LenLen", "note": "Thai, Flatiron", "list_name": "Hit List"},
    {"name": "Kelang", "note": "Malaysian, Greenpoint", "list_name": "Hit List"},
    {"name": "New Absolute Bagels", "note": "Bagels, Upper West Side", "list_name": "Hit List"},
    {"name": "Pierogi Boys", "note": "Polish, Ridgewood", "list_name": "Hit List"},
]

SOURCE_URL = "https://www.theinfatuation.com/new-york"
SOURCE_LABEL = "The Infatuation (NYC restaurant reviews & guides)"


def get_hard_to_get_list() -> list[dict]:
    """Return hard-to-get venues for the agent (name, note, list_name)."""
    return [dict(v) for v in INFATUATION_HARD_TO_GET]


def get_for_agent() -> dict:
    """Return payload for agent tool: list + attribution."""
    return {
        "venues": get_hard_to_get_list(),
        "source_label": SOURCE_LABEL,
        "source_url": SOURCE_URL,
        "summary": "NYC restaurants that are among the toughest reservations, from The Infatuation's guides. You can set up a notify for any of these so the user gets alerted when Resy has availability.",
    }

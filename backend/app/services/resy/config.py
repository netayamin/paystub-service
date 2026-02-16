"""Resy API config. Credentials from env (RESY_API_KEY, RESY_AUTH_TOKEN) or ResyClient args."""
import os
from pathlib import Path

from dotenv import load_dotenv

_ENV_PATH = Path(__file__).resolve().parent.parent.parent.parent / ".env"
load_dotenv(_ENV_PATH)

DEFAULT_BASE_URL = "https://api.resy.com"


def _env(key: str, default: str = "") -> str:
    return (os.getenv(key) or default).strip()


# Resy venue search uses a bounding box only (no radius parameter in the API).
# Box format: [min_lat, min_lng, max_lat, max_lng] = [south, west, north, east].
# Tuned to cover Manhattan: downtown (Battery Park) through upper Manhattan (Harlem, Inwood).
VENUE_SEARCH_TEST_BOUNDING_BOX: list[float] = [
    40.691,    # south — below Battery Park (downtown)
    -74.030,   # west — Hudson River
    40.882,    # north — Inwood / top of Manhattan (was 40.766, only ~96th St)
    -73.910,   # east — East River / beyond to catch all Manhattan
]

# Optional: expand the box by this many degrees on each side to widen the search area.
# ~0.01 deg ≈ 1.1 km; 0.05 ≈ 5.5 km. Set RESY_SEARCH_BOX_EXPAND_DEGREES in .env to extend.
def get_venue_search_bounding_box() -> list[float]:
    """Bounding box for venue search; expanded by RESY_SEARCH_BOX_EXPAND_DEGREES if set."""
    box = list(VENUE_SEARCH_TEST_BOUNDING_BOX)
    try:
        expand = float(_env("RESY_SEARCH_BOX_EXPAND_DEGREES", "0"))
    except ValueError:
        expand = 0.0
    if expand > 0:
        box[0] -= expand   # south
        box[1] -= expand   # west
        box[2] += expand   # north
        box[3] += expand   # east
    return box


class ResyConfig:
    """API credentials and base URL for Resy."""

    __slots__ = ("api_key", "auth_token", "base_url")

    def __init__(
        self,
        *,
        api_key: str | None = None,
        auth_token: str | None = None,
        base_url: str = DEFAULT_BASE_URL,
    ) -> None:
        self.api_key = (api_key or _env("RESY_API_KEY")).strip()
        self.auth_token = (auth_token or _env("RESY_AUTH_TOKEN")).strip()
        self.base_url = base_url.rstrip("/")

    def is_configured(self) -> bool:
        return bool(self.api_key and self.auth_token)

    def headers(self) -> dict[str, str]:
        return {
            "Authorization": f'ResyAPI api_key="{self.api_key}"',
            "x-resy-auth-token": self.auth_token,
            "Origin": "https://resy.com",
            "Referer": "https://resy.com/",
            "Content-Type": "application/json",
        }

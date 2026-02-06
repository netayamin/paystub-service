"""Resy API config. Credentials from env (RESY_API_KEY, RESY_AUTH_TOKEN) or ResyClient args."""
import os
from pathlib import Path

from dotenv import load_dotenv

_ENV_PATH = Path(__file__).resolve().parent.parent.parent.parent / ".env"
load_dotenv(_ENV_PATH)

DEFAULT_BASE_URL = "https://api.resy.com"


def _env(key: str, default: str = "") -> str:
    return (os.getenv(key) or default).strip()


VENUE_SEARCH_TEST_BOUNDING_BOX: list[float] = [
    40.69104047168222,
    -74.029110393126,
    40.7662954166697,
    -73.97769781072854,
]


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

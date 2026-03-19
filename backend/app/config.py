"""
Application settings (Pydantic Settings).
"""
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings

# .env next to backend/ (parent of app/)
_env_path = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    database_url: str = "postgresql://paystub:paystub@localhost:5432/paystub"
    openai_api_key: str = ""  # OPENAI_API_KEY in .env
    ai_model: str = "openai:gpt-4.1-mini"
    # Resy: RESY_API_KEY and RESY_AUTH_TOKEN in .env (from browser)
    resy_api_key: str = ""
    resy_auth_token: str = ""

    class Config:
        env_file = _env_path
        extra = "ignore"

    @field_validator("resy_api_key", "resy_auth_token", mode="after")
    @classmethod
    def strip_resy(cls, v: str) -> str:
        return (v or "").strip()


settings = Settings()

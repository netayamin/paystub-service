"""
Application settings (Pydantic Settings).
"""
from pathlib import Path

from pydantic import Field, field_validator
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

    # False on API-only replicas when running multiple uvicorn workers / hosts; one instance must stay True.
    enable_background_scheduler: bool = Field(default=True, validation_alias="ENABLE_BACKGROUND_SCHEDULER")
    # SQLAlchemy pool per process — lower these when running many Uvicorn workers (or use PgBouncer).
    db_pool_size: int = Field(default=8, ge=1, le=64, validation_alias="DB_POOL_SIZE")
    db_max_overflow: int = Field(default=10, ge=0, le=128, validation_alias="DB_MAX_OVERFLOW")

    class Config:
        env_file = _env_path
        extra = "ignore"

    @field_validator("resy_api_key", "resy_auth_token", mode="after")
    @classmethod
    def strip_resy(cls, v: str) -> str:
        return (v or "").strip()

    @field_validator("enable_background_scheduler", mode="before")
    @classmethod
    def parse_scheduler_flag(cls, v):
        if isinstance(v, bool):
            return v
        if v is None or v == "":
            return True
        s = str(v).strip().lower()
        if s in ("0", "false", "no", "off"):
            return False
        return s in ("1", "true", "yes", "on")


settings = Settings()

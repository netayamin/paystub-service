"""Resy agent: venue search. Instructions loaded from resy_agent_instructions.md."""
from datetime import date
from pathlib import Path

from pydantic_ai import Agent
from pydantic_ai.settings import ModelSettings

from app.agents.deps import ResyDeps
from app.config import settings
from app.toolsets.resy.tools import resy_toolset

_INSTRUCTIONS_PATH = Path(__file__).resolve().parent / "resy_agent_instructions.md"
_today = date.today().isoformat()
SYSTEM_PROMPT = _INSTRUCTIONS_PATH.read_text().strip().replace("{{current_date}}", _today)

agent = Agent(
    model=settings.ai_model,
    deps_type=ResyDeps,
    instructions=SYSTEM_PROMPT,
    toolsets=[resy_toolset],
    retries=1,
    model_settings=ModelSettings(max_tokens=16384),
)

"""
Agent registry: maps agent names to (agent, deps_factory) for the orchestrator.
"""
from collections.abc import Callable
from typing import Any

from sqlalchemy.orm import Session

from app.agents.deps import ResyDeps
from app.agents.resy_agent import agent as resy_agent

# Type: deps_factory(db, session_id?) -> deps instance for the agent
DepsFactory = Callable[..., Any]

# Registry: agent_name -> (agent, deps_factory)
_agents: dict[str, tuple[Any, DepsFactory]] = {}


def register(name: str, agent: Any, deps_factory: DepsFactory) -> None:
    """Register an agent and its deps factory."""
    _agents[name] = (agent, deps_factory)


def get(name: str) -> tuple[Any, DepsFactory] | None:
    """Return (agent, deps_factory) for the given name, or None."""
    return _agents.get(name)


def agent_names() -> list[str]:
    """Return registered agent names (e.g. for routing)."""
    return list(_agents.keys())


def _resy_deps_factory(db: Session, session_id: str | None = None) -> ResyDeps:
    return ResyDeps(db=db, session_id=session_id)


register("resy", resy_agent, _resy_deps_factory)

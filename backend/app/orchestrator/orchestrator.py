"""
Orchestrator: receives chat requests, routes to the Resy booking agent, returns response.
"""
from collections.abc import AsyncIterator
from typing import Any

from pydantic_ai.messages import PartDeltaEvent, PartStartEvent, TextPart, TextPartDelta
from pydantic_ai.run import AgentRunResultEvent

from app.orchestrator.registry import get
from sqlalchemy.orm import Session


def _route(message: str) -> str:
    return "resy"


async def run(
    message: str,
    db: Session,
    *,
    message_history: list[Any] | None = None,
    session_id: str | None = None,
) -> tuple[str, Any]:
    agent_name = _route(message)
    entry = get(agent_name)
    if not entry:
        return (f"No agent registered for: {agent_name}.", None)

    agent, deps_factory = entry
    deps = deps_factory(db, session_id)
    result = None
    last_exc: BaseException | None = None
    for attempt in range(2):
        try:
            result = await agent.run(message, deps=deps, message_history=message_history or [])
            break
        except BaseException as e:
            last_exc = e
            if attempt == 0:
                continue
            raise
    if result is None and last_exc is not None:
        raise last_exc

    text = result.output if isinstance(result.output, str) else str(result.output)
    return (text, result)


async def run_stream(
    message: str,
    db: Session,
    *,
    message_history: list[Any] | None = None,
    session_id: str | None = None,
) -> AsyncIterator[tuple[str, str | Any]]:
    agent_name = _route(message)
    entry = get(agent_name)
    if not entry:
        yield ("error", f"No agent registered for: {agent_name}.")
        return

    agent, deps_factory = entry
    deps = deps_factory(db, session_id)
    try:
        async for event in agent.run_stream_events(
            message, deps=deps, message_history=message_history or []
        ):
            if isinstance(event, PartStartEvent) and isinstance(event.part, TextPart):
                if event.part.content:
                    yield ("text", event.part.content)
            elif isinstance(event, PartDeltaEvent) and isinstance(event.delta, TextPartDelta):
                if event.delta.content_delta:
                    yield ("text", event.delta.content_delta)
            elif isinstance(event, AgentRunResultEvent):
                # Send venue list to sidebar so UI doesn't need to parse chat (saves tokens).
                if getattr(deps, "last_venue_search", None):
                    yield ("venues", deps.last_venue_search)
                yield ("result", event.result)
                return
    except BaseException as e:
        yield ("error", str(e))

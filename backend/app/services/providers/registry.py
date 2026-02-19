"""Registry of availability providers. Add new clients here."""
import logging
from typing import Any

logger = logging.getLogger(__name__)

_providers: dict[str, Any] = {}


def register(name: str, provider: Any) -> None:
    """Register a provider (e.g. 'resy', 'opentable')."""
    _providers[name] = provider
    logger.info("Registered availability provider: %s", name)


def get_provider(name: str) -> Any:
    """Get provider by name. Raises KeyError if unknown."""
    if name not in _providers:
        raise KeyError(f"Unknown provider: {name}. Available: {list(_providers.keys())}")
    return _providers[name]


def list_providers() -> list[str]:
    """List registered provider ids."""
    return list(_providers.keys())


def _init_registry() -> None:
    from app.services.providers.resy_provider import ResyProvider
    from app.services.providers.opentable_provider import OpenTableProvider

    register("resy", ResyProvider())
    register("opentable", OpenTableProvider())


# Register built-in providers on first import
_init_registry()

"""
Availability providers: Resy, OpenTable, etc.
Each provider fetches data in its own way but returns the same normalized shape
so discovery (buckets, drop_events, feed, new-drops) stays provider-agnostic.
"""
from app.services.providers.base import AvailabilityProvider
from app.services.providers.registry import get_provider, list_providers
from app.services.providers.types import NormalizedSlotResult

__all__ = [
    "AvailabilityProvider",
    "NormalizedSlotResult",
    "get_provider",
    "list_providers",
]

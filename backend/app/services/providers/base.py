"""Protocol for availability providers. All clients return the same normalized shape."""
from typing import Protocol

from app.services.providers.types import NormalizedSlotResult


class AvailabilityProvider(Protocol):
    """Interface for Resy, OpenTable, etc. Same contract; only fetch differs."""

    @property
    def provider_id(self) -> str:
        """Unique id (e.g. 'resy', 'opentable') for slot_id and DropEvent.provider."""
        ...

    def search_availability(
        self,
        date_str: str,
        time_slot: str,
        party_sizes: list[int],
    ) -> list[NormalizedSlotResult]:
        """
        Fetch current availability for one bucket (date + time anchor).
        Returns one NormalizedSlotResult per (venue, time) slot.
        """
        ...

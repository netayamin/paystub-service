"""
NYC hotspot venues. Re-exports from core.hotspots for backward compatibility.
"""
from app.core.hotspots import (
    NYC_HOTSPOT_NAMES,
    is_hotspot,
    list_hotspots,
)

__all__ = ["NYC_HOTSPOT_NAMES", "is_hotspot", "list_hotspots"]

"""Extract display/profile fields from Resy-style venue payloads (shared by poll + backfill)."""


def venue_profile_from_payload(payload: dict | None) -> tuple[str | None, str | None, str | None]:
    """Return (image_url, neighborhood, resy_url) from payload; strings truncated for DB columns."""
    if not isinstance(payload, dict):
        return None, None, None
    neighborhood_val = None
    loc = payload.get("location")
    nh = payload.get("neighborhood") or (loc.get("neighborhood") if isinstance(loc, dict) else None)
    if nh is not None:
        neighborhood_val = str(nh)[:128] or None
    image_url_val = None
    img = payload.get("image_url")
    if isinstance(img, str) and img.strip():
        image_url_val = img.strip()[:512]
    else:
        images = payload.get("images")
        if isinstance(images, dict):
            for key in ("thumbnail", "small", "medium"):
                u = images.get(key)
                if isinstance(u, str) and u.strip():
                    image_url_val = u.strip()[:512]
                    break
    raw_resy = payload.get("resy_url") or payload.get("resyUrl") or payload.get("book_url")
    resy_url_val = str(raw_resy).strip()[:512] if isinstance(raw_resy, str) and raw_resy.strip() else None
    return image_url_val, neighborhood_val, resy_url_val

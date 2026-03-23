"""Extract display/profile fields from Resy-style venue payloads (shared by poll + backfill)."""


def normalize_http_url(url: str | None, *, max_len: int = 512) -> str | None:
    """Ensure URL has a scheme (Resy often returns protocol-relative //cdn...)."""
    if not url or not isinstance(url, str):
        return None
    u = url.strip()
    if not u:
        return None
    if u.startswith("//"):
        u = "https:" + u
    elif not (u.startswith("http://") or u.startswith("https://")):
        if "://" not in u[:16]:
            u = "https://" + u
    return u[:max_len] if u else None


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
        image_url_val = normalize_http_url(img.strip())
    else:
        images = payload.get("images")
        if isinstance(images, dict):
            for key in ("thumbnail", "small", "medium"):
                u = images.get(key)
                if isinstance(u, str) and u.strip():
                    image_url_val = normalize_http_url(u.strip())
                    break
    raw_resy = payload.get("resy_url") or payload.get("resyUrl") or payload.get("book_url")
    resy_url_val = (
        normalize_http_url(str(raw_resy).strip()) if isinstance(raw_resy, str) and raw_resy.strip() else None
    )
    return image_url_val, neighborhood_val, resy_url_val

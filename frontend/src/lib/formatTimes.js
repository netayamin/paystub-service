/**
 * Shared formatters for time/date display (watches, notifications, availability).
 */

export function formatTimeSlot(slot) {
  if (!slot || typeof slot !== "string") return "";
  const s = slot.trim().replace(/\+\d+$/, "");
  const timePart = s.includes(" ") ? s.split(" ").pop() : s;
  const [h, m] = timePart.split(":").map(Number);
  if (Number.isNaN(h)) return slot;
  const d = new Date(2000, 0, 1, h, m || 0);
  const formatted = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  // Convert "7:00 PM" to "7:00pm"
  return formatted.replace(/\s*(AM|PM)$/i, (match) => match.trim().toLowerCase());
}

/** Compact time for inventory grid: "7:00pm", "9:30pm" */
export function formatTimeSlotCompact(slot) {
  if (!slot || typeof slot !== "string") return "—";
  const parsed = parseTimeSlotToMinutes(slot);
  if (parsed == null) return slot.trim().length ? slot : "—";
  const hour = Math.floor(parsed / 60);
  const min = parsed % 60;
  const ampm = hour >= 12 ? "pm" : "am";
  const hour12 = hour % 12 || 12;
  return min ? `${hour12}:${String(min).padStart(2, "0")}${ampm}` : `${hour12}:00${ampm}`;
}

/** Parse "18:15", "18:15:00", "2026-02-06 18:15:00", or "18:15+1" to minutes since midnight, or null. Strips +1/+2 (day offset) so we display only the time. */
function parseTimeSlotToMinutes(slot) {
  if (!slot || typeof slot !== "string") return null;
  const s = slot.trim().replace(/\+\d+$/, "");
  const timePart = s.includes(" ") ? s.split(" ").pop() : s;
  const parts = timePart.split(":").map(Number);
  const h = parts[0];
  const m = parts[1] || 0;
  if (Number.isNaN(h) || h < 0 || h > 23) return null;
  return h * 60 + (Number.isNaN(m) ? 0 : Math.min(59, Math.max(0, m)));
}

/** True if any slot in availabilityTimes falls within [startMinutes, endMinutes] (inclusive). Minutes since midnight. */
export function hasAvailabilityInWindow(availabilityTimes, startMinutes, endMinutes) {
  const raw = Array.isArray(availabilityTimes) ? availabilityTimes : [];
  return raw.some((slot) => {
    const m = parseTimeSlotToMinutes(slot);
    return m != null && m >= startMinutes && m <= endMinutes;
  });
}

/**
 * Return only availability times that are still in the future for the given date (local).
 * Resy can return stale times; we filter so we never show 8:00 PM after 8pm has passed.
 */
export function getFutureAvailabilityTimes(dateStr, availabilityTimes) {
  if (!dateStr || !Array.isArray(availabilityTimes) || availabilityTimes.length === 0) return [];
  const now = new Date();
  const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
  if (dateStr !== today) return availabilityTimes;
  return availabilityTimes.filter((slot) => {
    const m = parseTimeSlotToMinutes(slot);
    if (m == null) return true;
    const nowMin = now.getHours() * 60 + now.getMinutes();
    return m > nowMin;
  });
}

/** If multiple availability times, show range "6:15pm – 7:15pm"; if one, show that time; if none, "—". */
export function formatAvailabilityTimeRange(availabilityTimes) {
  const raw = Array.isArray(availabilityTimes) ? availabilityTimes : [];
  const minutes = raw.map(parseTimeSlotToMinutes).filter((n) => n != null);
  if (minutes.length === 0) return "—";
  const minM = Math.min(...minutes);
  const maxM = Math.max(...minutes);
  const fmt = (m) => {
    const hour = Math.floor(m / 60);
    const min = m % 60;
    const ampm = hour >= 12 ? "pm" : "am";
    const hour12 = hour % 12 || 12;
    return min ? `${hour12}:${String(min).padStart(2, "0")}${ampm}` : `${hour12}:00${ampm}`;
  };
  if (minutes.length === 1) return fmt(minM);
  return `${fmt(minM)} – ${fmt(maxM)}`;
}

export function formatLastChecked(iso) {
  if (!iso) return null;
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return "Checked just now";
    const min = Math.floor(sec / 60);
    if (min < 60) return `Checked ${min} min ago`;
    const sameDay = d.toDateString() === now.toDateString();
    return sameDay
      ? `Checked at ${d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`
      : `Checked ${d.toLocaleDateString()}`;
  } catch {
    return null;
  }
}

export function formatNotificationTime(iso) {
  if (!iso) return null;
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return "Just now";
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min} min ago`;
    const sameDay = d.toDateString() === now.toDateString();
    return sameDay
      ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      : d.toLocaleString();
  } catch {
    return null;
  }
}

/** Short label for cards: "JUST NOW", "2M AGO", "15M AGO", "1H AGO" */
export function formatTimeAgoShort(iso) {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return "JUST NOW";
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min}M AGO`;
    const h = Math.floor(min / 60);
    if (h < 24) return `${h}H AGO`;
    return `${Math.floor(h / 24)}D AGO`;
  } catch {
    return "";
  }
}

/** Red pill badge: "12S AGO", "2M AGO", "1H AGO" (for LIVE DROP FEED cards) */
export function formatTimeAgoBadge(iso) {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return `${sec}S AGO`;
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min}M AGO`;
    const h = Math.floor(min / 60);
    if (h < 24) return `${h}H AGO`;
    return `${Math.floor(h / 24)}D AGO`;
  } catch {
    return "";
  }
}

/** Section label from iso: "SECONDS AGO" | "2M AGO" | "1H AGO" (for "FOUND X AGO" grouping) */
export function formatTimeAgoSectionLabel(iso) {
  if (!iso) return "RECENT";
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return "SECONDS AGO";
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min}M AGO`;
    const h = Math.floor(min / 60);
    if (h < 24) return `${h}H AGO`;
    return `${Math.floor(h / 24)}D AGO`;
  } catch {
    return "RECENT";
  }
}

/** Sentence form: "Just now", "4s ago", "2m ago" (for "Updated 4s ago") */
export function formatTimeAgoSentence(iso) {
  if (!iso) return "Just now";
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return sec <= 1 ? "Just now" : `${sec}s ago`;
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min}m ago`;
    const h = Math.floor(min / 60);
    if (h < 24) return `${h}h ago`;
    return `${Math.floor(h / 24)}d ago`;
  } catch {
    return "Just now";
  }
}

/** Feed copy: "Just dropped", "Dropped 14 min ago" — for emotional punch on cards */
export function formatDropCopy(iso) {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const now = new Date();
    const sec = Math.floor((now - d) / 1000);
    if (sec < 60) return "Just dropped";
    const min = Math.floor(sec / 60);
    if (min < 60) return `Dropped ${min} min ago`;
    const h = Math.floor(min / 60);
    if (h < 24) return `Dropped ${h} hr ago`;
    return `Dropped ${Math.floor(h / 24)} days ago`;
  } catch {
    return "";
  }
}

export function formatNextCheck(lastCheckedAtIso, intervalMinutes, nowMs) {
  if (!lastCheckedAtIso) return "First check pending…";
  const last = new Date(lastCheckedAtIso).getTime();
  const next = last + (intervalMinutes || 2) * 60 * 1000;
  const remaining = next - nowMs;
  if (remaining <= 0) return "Checking now…";
  const totalSec = Math.ceil(remaining / 1000);
  if (totalSec < 60) return `Next check in ${totalSec}s`;
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `Next check in ${m}:${String(s).padStart(2, "0")}`;
}

export function formatSessionDate(iso) {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    const now = new Date();
    const sameDay = d.toDateString() === now.toDateString();
    return sameDay
      ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      : d.toLocaleDateString();
  } catch {
    return "";
  }
}

/** Watchlist card date: "Fri, Aug 16" from YYYY-MM-DD */
export function formatWatchlistDate(dateStr) {
  if (!dateStr || typeof dateStr !== "string") return "";
  try {
    const d = new Date(dateStr.trim() + "T12:00:00");
    if (Number.isNaN(d.getTime())) return "";
    return d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
  } catch {
    return "";
  }
}

/** Watchlist card time label: "7:00pm", "All Eve", or "Any Time" */
export function formatWatchlistTime(timeFilter) {
  if (!timeFilter || typeof timeFilter !== "string") return "Any Time";
  const t = timeFilter.trim();
  if (!t) return "Any Time";
  const [h, m] = t.split(":").map(Number);
  if (Number.isNaN(h)) return t;
  if (h >= 17) return "All Eve";
  const d = new Date(2000, 0, 1, h, m || 0);
  const formatted = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  // Convert "7:00 PM" to "7:00pm"
  return formatted.replace(/\s*(AM|PM)$/i, (match) => match.trim().toLowerCase());
}

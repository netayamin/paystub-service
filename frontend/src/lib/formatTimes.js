/**
 * Shared formatters for time/date display (watches, notifications, availability).
 */

export function formatTimeSlot(slot) {
  if (!slot || typeof slot !== "string") return "";
  const [h, m] = slot.trim().split(":").map(Number);
  if (Number.isNaN(h)) return slot;
  const d = new Date(2000, 0, 1, h, m || 0);
  return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
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

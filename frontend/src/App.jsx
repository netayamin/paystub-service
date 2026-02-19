import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatTimeAgoBadge, formatTimeAgoSectionLabel, formatAvailabilityTimeRange, formatTimeAgoSentence, formatDropCopy, getFutureAvailabilityTimes } from "@/lib/formatTimes";
import { motion, AnimatePresence } from "motion/react";
import {
  Zap,
  Flame,
  Sparkles,
  ExternalLink,
  ChevronDown,
  X,
  Bell,
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
  DropdownMenuCheckboxItem,
} from "@/components/ui/dropdown-menu";

// In dev, same origin (Vite proxies /chat and /resy). In production, set VITE_API_URL to your backend URL (e.g. https://your-app.railway.app).
const API_BASE = import.meta.env.VITE_API_URL ?? "";

/** Parse "HH:MM" to minutes since midnight for comparison. */
function timeToMins(t) {
  if (!t) return 0;
  const [h, m] = String(t).split(":").map(Number);
  return (h || 0) * 60 + (m || 0);
}
function minsToTime(m) {
  const mins = Math.round(Number(m)) || 0;
  const h = Math.floor(mins / 60);
  const min = mins % 60;
  return `${h}:${String(min).padStart(2, "0")}`;
}

/** Curated list of notoriously hard-to-book, high-demand NYC restaurants */
const HOT_RESTAURANTS = new Set([
  // Italian
  "Carbone", "I Sodi", "Don Angie", "Lilia", "Torrisi", "Parm", "Via Carota",
  "L'Artusi", "Rezdôra", "Cecconi's", "Barbuto", "Marea",
  // Fine Dining / Contemporary
  "4 Charles Prime Rib", "Le Bernardin", "Eleven Madison Park", "Per Se",
  "The Grill", "The Pool", "Balthazar", "Daniel", "Jean-Georges",
  "Monkey Bar",
  // Sushi / Japanese
  "Sushi Nakazawa", "Cote", "Odo", "Yoshino", "Noda", "Sushi Noz",
  "Torien", "BONDST", "Blue Ribbon Sushi",
  // French
  "Le Coucou", "Frenchette", "Buvette", "La Mercerie", "Chez Zou",
  "Claudette", "La Pecora Bianca",
  // Steakhouse
  "Peter Luger", "Cote", "Quality Meats", "The Grill", "Sparks",
  // Other / Trendy
  "Altro Paradiso", "Laser Wolf", "The Four Horsemen", "Sailor",
  "Penny", "HAGS", "Joji", "Claud", "Dame", "The River Café",
  "Cervo's", "Misi", "Pastis", "Minetta Tavern", "Scarr's Pizza",
  "Rosella", "Gaia", "Tatiana", "Gramercy Tavern", "The Spotted Pig",
  "Gage & Tollner", "Francie", "Gem", "Nura", "Place des Fêtes",
  "Superiority Burger", "Estela", "King",
  // Brooklyn
  "Gage & Tollner", "Francie", "Lilia", "Misi", "Aska", "Oxalis",
  "Olmsted", "Al Di Là", "Hometown BBQ",
]);

/** Names that always get a slot in Top Opportunities when they exist in the feed */
const TOP_OPPORTUNITY_PRIORITY_NAMES = ["Monkey Bar", "I Sodi", "Tatiana"];

function isHotRestaurant(name) {
  if (!name) return false;
  const normalized = name.toLowerCase().trim();
  for (const hotName of HOT_RESTAURANTS) {
    if (normalized.includes(hotName.toLowerCase()) || hotName.toLowerCase().includes(normalized)) {
      return true;
    }
  }
  return false;
}

function isTopOpportunityPriority(name) {
  if (!name) return false;
  const n = name.toLowerCase().trim();
  return TOP_OPPORTUNITY_PRIORITY_NAMES.some((p) => n.includes(p.toLowerCase()) || p.toLowerCase().includes(n));
}

/** "Feb 06" from YYYY-MM-DD */
function formatMonthDay(dateStr) {
  if (!dateStr || typeof dateStr !== "string") return "";
  try {
    const d = new Date(dateStr.trim() + "T12:00:00");
    const month = d.toLocaleDateString("en-US", { month: "short" });
    const day = dateStr.slice(-2);
    return `${month} ${day}`;
  } catch {
    return dateStr;
  }
}

/** "Sat" from YYYY-MM-DD (for pill copy) */
function formatDayShort(dateStr) {
  if (!dateStr || typeof dateStr !== "string") return dateStr;
  try {
    const d = new Date(dateStr.trim() + "T12:00:00");
    return d.toLocaleDateString("en-US", { weekday: "short" });
  } catch {
    return dateStr;
  }
}

/** "5:15 PM" from time string */
function formatTimeForSlot(timeStr) {
  if (!timeStr || typeof timeStr !== "string") return "";
  const t = timeStr.split("–")[0].trim();
  const match = t.match(/(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?/);
  if (match) return `${match[1]}:${match[2]} ${(match[3] || "").toUpperCase()}`;
  const simple = t.match(/(\d{1,2})\s*(AM|PM|am|pm)/i);
  return simple ? `${simple[1]}:00 ${simple[2].toUpperCase()}` : t;
}

/** Signal label for notification: meaning, not hype */
function getDropSignalLabel(drop, isHot) {
  if (!drop) return "New opening";
  const popularity = drop.resy_popularity_score ?? (drop.rating_count > 100 ? 0.8 : 0);
  if (isHot || (typeof popularity === "number" && popularity > 0.7)) return "High demand";
  if (drop.rating_count > 500) return "Usually fully booked";
  return "New opening";
}

/** "WED, FEB 06" from YYYY-MM-DD */
function formatDayAndDate(dateStr) {
  if (!dateStr || typeof dateStr !== "string") return "";
  try {
    const d = new Date(dateStr.trim() + "T12:00:00");
    const dayName = d.toLocaleDateString("en-US", { weekday: "short" }).toUpperCase();
    const month = d.toLocaleDateString("en-US", { month: "short" }).toUpperCase();
    const day = dateStr.slice(-2);
    return `${dayName}, ${month} ${day}`;
  } catch {
    return dateStr;
  }
}

/** User-friendly party size label: "for 2 people", "for 2 or 3 people", etc. */
function formatPartySizeLabel(sizes) {
  if (!sizes || sizes.length === 0) return "for 2 people";
  const n = sizes.map(Number).filter(Boolean);
  if (n.length === 0) return "for 2 people";
  if (n.length === 1) return `for ${n[0]} people`;
  if (n.length === 2) return `for ${n[0]} or ${n[1]} people`;
  const last = n[n.length - 1];
  const rest = n.slice(0, -1).join(", ");
  return `for ${rest} or ${last} people`;
}

/** Short party size next to time: "2 people", "2 or 3 people" */
function formatPartySizeShort(sizes) {
  if (!sizes || sizes.length === 0) return "2 people";
  const n = sizes.map(Number).filter(Boolean);
  if (n.length === 0) return "2 people";
  if (n.length === 1) return `${n[0]} people`;
  if (n.length === 2) return `${n[0]} or ${n[1]} people`;
  const last = n[n.length - 1];
  const rest = n.slice(0, -1).join(", ");
  return `${rest} or ${last} people`;
}

/** Compact time for badge: "45s", "2m", "12m", "1h", "2d" */
function formatTimeAgoCompact(secondsAgo) {
  if (secondsAgo >= 999 || secondsAgo < 0) return "";
  if (secondsAgo < 60) return `${secondsAgo}s`;
  const min = Math.floor(secondsAgo / 60);
  if (min < 60) return `${min}m`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

/** Countdown to next scan: "Scan in 1m 23s", "Scan in 45s", or "Scanning…" when due/past. */
function formatNextScanCountdown(nextScanAt) {
  if (!nextScanAt || !(nextScanAt instanceof Date)) return null;
  const sec = Math.max(0, Math.round((nextScanAt.getTime() - Date.now()) / 1000));
  if (sec <= 0) return "Scanning…";
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  if (m > 0) return `Scan in ${m}m ${String(s).padStart(2, "0")}s`;
  return `Scan in ${s}s`;
}

/** Per-bucket scan age: "Just now" | "2m" | "1h" for display in date pill. */
function formatScanAgo(lastScanAtIso) {
  if (!lastScanAtIso) return "—";
  const t = new Date(lastScanAtIso).getTime();
  if (Number.isNaN(t)) return "—";
  const sec = Math.floor((Date.now() - t) / 1000);
  if (sec < 0) return "Just now";
  if (sec < 60) return "Just now";
  const m = Math.floor(sec / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

/** Single time indicator: "Added just now" (under 1 min) | "Added 5m ago" | "Recently" when unknown */
function formatAddedAgo(secondsAgo) {
  if (secondsAgo >= 999 || secondsAgo < 0) return "Recently";
  if (secondsAgo < 60) return "Added just now";
  const min = Math.floor(secondsAgo / 60);
  if (min < 60) return `Added ${min}m ago`;
  const h = Math.floor(min / 60);
  if (h < 24) return `Added ${h}h ago`;
  return `Added ${Math.floor(h / 24)}d ago`;
}

/** Time when detected — e.g. "2:30 PM", or "—" if missing (legacy; prefer getFreshnessLabel for cards) */
function formatTimeSinceDetected(detectedAt) {
  if (!detectedAt) return "—";
  const d = new Date(detectedAt);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit", hour12: true });
}

/**
 * Freshness badge: "Just now" (0–5 min), "Last 30 mins" (5–30), "Last hour" (30–60), null after 60 min.
 */
function getFreshnessLabel(detectedAt) {
  if (!detectedAt) return null;
  const d = new Date(detectedAt);
  if (Number.isNaN(d.getTime())) return null;
  const secondsAgo = (Date.now() - d.getTime()) / 1000;
  if (secondsAgo < 5 * 60) return "Just now";
  if (secondsAgo < 30 * 60) return "Last 30 mins";
  if (secondsAgo < 60 * 60) return "Last hour";
  return null;   // 60+ min: no badge
}

/** Slot label for chips: time only when all slots same date (less clutter), else "Sat Feb 12 · 8:00 PM" */
function formatSlotLabel(slot, sameDateOnly) {
  if (!slot) return "";
  const timeStr = formatTimeForSlot(slot.time);
  if (sameDateOnly) return timeStr;
  return `${formatDayShort(slot.date_str)} ${formatMonthDay(slot.date_str)} · ${timeStr}`;
}

/**
 * Build cards from API snapshot (just-opened or current_snapshot). Same shape: list of { date_str, venues, scanned_at }.
 * timeChip: "7:00 PM" | "8:00 PM" | "Anytime" — filters to venues with a slot in that window.
 */
function buildDiscoveryDrops(snapshotList, timeChip, options = {}) {
  if (!Array.isArray(snapshotList) || snapshotList.length === 0) return [];
  const startMin = timeChip === "7:00 PM" ? 19 * 60 : timeChip === "8:00 PM" ? 20 * 60 : null;
  const endMin = timeChip === "7:00 PM" ? 20 * 60 : timeChip === "8:00 PM" ? 21 * 60 : null;
  const filterByTime = startMin != null && endMin != null;
  const cards = [];
  for (const day of snapshotList) {
    const date_str = day.date_str;
    const scannedAt = day.scanned_at;
    const venues = day.venues || [];
    for (const v of venues) {
      const futureTimes = getFutureAvailabilityTimes(date_str, v.availability_times || []);
      if (futureTimes.length === 0) continue;
      if (filterByTime && !hasAvailabilityInWindow(futureTimes, startMin, endMin)) continue;
      const timeStr = formatAvailabilityTimeRange(futureTimes);
      // Release time: backend sends detected_at (or opened_at). Support snake_case and camelCase.
      const createdAt = v.detected_at ?? v.opened_at ?? v.detectedAt ?? v.openedAt ?? null;
      const venueKey = String(v.venue_id ?? v.name ?? "").trim() || "Venue";
      cards.push({
        id: `just-opened-${date_str}-${(v.name || "").replace(/\s+/g, "-")}`,
        name: v.name || "Venue",
        venueKey, // for unique-per-restaurant counts
        time: timeStr !== "—" ? timeStr : null,
        location: v.neighborhood || "NYC", // Show actual neighborhood
        date_str,
        subtitle: scannedAt ? `Scanned ${formatTimeAgoSentence(scannedAt)}` : "Available",
        isTableJustReleased: false, // Not used anymore
        resyUrl: v.resy_url ?? null,
        image_url: v.image_url ?? null,
        created_at: createdAt,
        detected_at: createdAt,
        party_sizes_available: v.party_sizes_available || [],
        source: "discovery",
        rating_average: v.rating_average,
        rating_count: v.rating_count,
        resy_collections: v.resy_collections,
        resy_popularity_score: v.resy_popularity_score,
      });
    }
  }
  return cards;
}

export default function App() {
  const [justOpened, setJustOpened] = useState([]); // GET /chat/watches/just-opened — hot drops
  const [stillOpen, setStillOpen] = useState([]);   // same API — drops from before that are still open
  /** When backend sends feed segments, use them instead of computing on the client */
  const [apiFeed, setApiFeed] = useState(null); // { ranked_board, top_opportunities, hot_right_now } | null
  /** All-dates just-opened for notifications (banner shows hot new drops for any date, not just selected) */
  const [notificationDropsAllDates, setNotificationDropsAllDates] = useState([]);
  const [calendarCounts, setCalendarCounts] = useState({ by_date: {}, dates: [] }); // GET /chat/watches/calendar-counts — for calendar bar graph
  const [justOpenedError, setJustOpenedError] = useState(null); // e.g. "Backend not reachable"
  const [nextScanAt, setNextScanAt] = useState(null); // next discovery scan run (Date), from API
  const [lastScanAt, setLastScanAt] = useState(null); // when the last discovery scan completed (Date)
  const [totalVenuesScanned, setTotalVenuesScanned] = useState(0); // total venues in last scan (so user sees system is active)
  const [bucketHealth, setBucketHealth] = useState([]); // per-bucket last_scan_at from GET /chat/watches/bucket-status
  const [notificationPermission, setNotificationPermission] = useState(
    () => (typeof window !== "undefined" && "Notification" in window ? Notification.permission : "default")
  );
  const todayStr = useMemo(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }, []);
  const today = new Date();
  const isPast11PM = today.getHours() >= 23;

  // Filter states
  const [selectedDates, setSelectedDates] = useState(new Set([todayStr]));
  const [selectedTimes, setSelectedTimes] = useState(new Set(["all"]));
  const [selectedPartySizes, setSelectedPartySizes] = useState(new Set([2, 3, 4, 5]));
  /** Dinner time range (backend time_range param). Default 6pm–8pm. */
  const [timeRangeStart, setTimeRangeStart] = useState("18:00");
  const [timeRangeEnd, setTimeRangeEnd] = useState("20:00");

  const selectedDateStr = selectedDates.size > 0 ? Array.from(selectedDates)[0] : todayStr;
  const isViewingToday = selectedDateStr === todayStr;
  const isThatsItForToday = isViewingToday && isPast11PM;

  /** Home = curated high signal. All = full list (scanning/exploration). */
  const [viewMode, setViewMode] = useState("home");
  
  // Live indicators
  const [scanProgress, setScanProgress] = useState(0);
  const [recentDropIds, setRecentDropIds] = useState(new Set());
  const [showAllDates, setShowAllDates] = useState(false);
  
  // New drop tracking
  const [seenDropIds, setSeenDropIds] = useState(new Set());
  const [newDropsCount, setNewDropsCount] = useState(0);
  /** First new drop's name + time for notification (e.g. "Pastis · Fri Feb 13 · 9:00 PM") */
  const [newDropsBannerLabel, setNewDropsBannerLabel] = useState("");
  /** Thumbnail for notification card (first drop's image) */
  const [newDropsBannerImageUrl, setNewDropsBannerImageUrl] = useState("");
  /** List of new drops for popup notification */
  const [newDropsList, setNewDropsList] = useState([]);
  const [newDropsByDate, setNewDropsByDate] = useState({});
  const [showNewDropsBanner, setShowNewDropsBanner] = useState(false);
  
  // UX: which cards have "View all times" expanded (set of drop.id)
  const [expandedSlotCardIds, setExpandedSlotCardIds] = useState(new Set());
  /** Date rail: default collapsed; clicking date pill opens slide-down panel */
  const [dateDrawerOpen, setDateDrawerOpen] = useState(false);
  /** Live ticker (Just Dropped) paused until timestamp; null = not paused */
  const [liveTickerPausedUntil, setLiveTickerPausedUntil] = useState(null);
  const isUserScrolledRef = useRef(false);
  const newDropsSectionRef = useRef(null);
  const [isNearTop, setIsNearTop] = useState(true);
  const newCardFirstSeenAt = useRef({});
  const muteToastsUntilRef = useRef(0);
  const [toasts, setToasts] = useState([]);
  const lastToastDropIdsRef = useRef(new Set());
  const newDropsSeenIdsRef = useRef(new Set()); // dedupe toasts within same poll
  const lastNewDropsAtRef = useRef(null); // last response "at" (ISO) — passed as since so backend returns only new drops
  const toastTimeoutsRef = useRef({});
  const alertDismissTimeoutRef = useRef(null);
  /** Notifications: session-only. Only "new drops the moment they happen" — no backlog from storage. */
  const [notifications, setNotifications] = useState([]);
  const [notificationPanelOpen, setNotificationPanelOpen] = useState(false);
  const unreadCount = useMemo(() => notifications.filter((n) => !n.read).length, [notifications]);
  /** Side update rail: ephemeral "Venue — time just opened" items, expire after 25s */
  const [sideUpdates, setSideUpdates] = useState([]);
  const sideUpdateTimeoutsRef = useRef({});
  const SIDE_UPDATE_TTL_MS = 25000;
  const SIDE_UPDATE_MAX = 5;
  const allDropsAlerts = true; // Always show all drops (no Hot/All choice)
  const [otherDayHotCountByDate, setOtherDayHotCountByDate] = useState({}); // { date_str: count } for Hot drops on non-selected days (14-day range)
  const HAPPENING_NOW_SECONDS = 90;
  const NEW_BADGE_SECONDS = 300; // 5 min — then show "Last 30 mins" / "Last hour" then remove

  const fetchJustOpened = useCallback(async () => {
    setJustOpenedError(null);
    try {
      const params = new URLSearchParams();
      // Date filter: backend returns only selected dates
      if (selectedDates.size > 0) {
        params.set("dates", Array.from(selectedDates).join(","));
      }
      // Time filter: pass time_range (or time_after/time_before) so backend filters. Only when user has selected a time other than "All" (e.g. Dinner).
      if (!selectedTimes.has("all") && selectedTimes.size > 0) {
        const ranges = [];
        if (selectedTimes.has("lunch")) ranges.push({ after: "11:00", before: "15:00" });
        if (selectedTimes.has("3pm")) ranges.push({ after: "15:00", before: "18:00" });
        if (selectedTimes.has("dinner")) {
          let start = timeRangeStart || "18:00";
          let end = timeRangeEnd || "20:00";
          if (timeToMins(end) <= timeToMins(start)) {
            [start, end] = [end, start]; // ensure start < end so backend applies filter (else returns unfiltered = huge list)
          }
          ranges.push({ after: start, before: end });
        }
        if (ranges.length === 1) {
          params.set("time_range", `${ranges[0].after}-${ranges[0].before}`);
        } else if (ranges.length > 1) {
          const minAfter = ranges.reduce((a, r) => (r.after < a ? r.after : a), ranges[0].after);
          const maxBefore = ranges.reduce((a, r) => (r.before > a ? r.before : a), ranges[0].before);
          params.set("time_after", minAfter);
          params.set("time_before", maxBefore);
        }
        const slots = [];
        if (selectedTimes.has("lunch") || selectedTimes.has("3pm")) slots.push("15:00");
        if (selectedTimes.has("dinner")) slots.push("19:00");
        if (slots.length) params.set("time_slots", slots.join(","));
      }
      if (selectedPartySizes.size > 0 && selectedPartySizes.size < 4) {
        params.set("party_sizes", Array.from(selectedPartySizes).sort((a, b) => a - b).join(","));
      }
      params.set("_t", String(Date.now()));
      const qs = params.toString();
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000);
      const res = await fetch(`${API_BASE}/chat/watches/just-opened?${qs}`, { signal: controller.signal });
      clearTimeout(timeoutId);
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        setJustOpened(Array.isArray(data.just_opened) ? data.just_opened : []);
        setStillOpen(Array.isArray(data.still_open) ? data.still_open : []);
        if (Array.isArray(data.ranked_board) && Array.isArray(data.top_opportunities) && Array.isArray(data.hot_right_now)) {
          setApiFeed({
            ranked_board: data.ranked_board,
            top_opportunities: data.top_opportunities,
            hot_right_now: data.hot_right_now,
          });
        } else {
          setApiFeed(null);
        }
        // Fetch calendar counts for the bar graph (same data source, no date filter)
        const countsRes = await fetch(`${API_BASE}/chat/watches/calendar-counts`);
        const countsData = await countsRes.json().catch(() => ({}));
        if (countsRes.ok && countsData.by_date) {
          setCalendarCounts({ by_date: countsData.by_date, dates: Array.isArray(countsData.dates) ? countsData.dates : [] });
        }
        try {
          const bucketRes = await fetch(`${API_BASE}/chat/watches/bucket-status?_t=${Date.now()}`);
          const bucketData = await bucketRes.json().catch(() => ({}));
          if (bucketRes.ok && Array.isArray(bucketData.buckets)) {
            setBucketHealth(bucketData.buckets);
          }
        } catch (_) {
          setBucketHealth([]);
        }
        if (data.next_scan_at) {
          const d = new Date(data.next_scan_at);
          if (!Number.isNaN(d.getTime())) setNextScanAt(d);
          else setNextScanAt(null);
        } else setNextScanAt(null);
        if (data.last_scan_at) {
          const d = new Date(data.last_scan_at);
          setLastScanAt(Number.isNaN(d.getTime()) ? null : d);
        } else setLastScanAt(null);
        setTotalVenuesScanned(typeof data.total_venues_scanned === "number" ? data.total_venues_scanned : 0);
        // Fetch just-opened for all dates (no date filter) so notifications appear for any date, not just selected
        try {
          const notifRes = await fetch(`${API_BASE}/chat/watches/just-opened?_t=${Date.now()}`);
          const notifData = await notifRes.json().catch(() => ({}));
          if (notifRes.ok && Array.isArray(notifData.just_opened)) {
            const allDatesDrops = buildDiscoveryDrops(notifData.just_opened, "Anytime");
            setNotificationDropsAllDates(allDatesDrops);
          } else {
            setNotificationDropsAllDates([]);
          }
        } catch (_) {
          setNotificationDropsAllDates([]);
        }
        // New-drops: backend returns only drops detected after last poll when since= is sent
        try {
          const sinceParam = lastNewDropsAtRef.current ? `&since=${encodeURIComponent(lastNewDropsAtRef.current)}` : "";
          const newDropsRes = await fetch(`${API_BASE}/chat/watches/new-drops?within_minutes=15${sinceParam}&_t=${Date.now()}`);
          const newDropsData = await newDropsRes.json().catch(() => ({}));
          if (newDropsRes.ok && newDropsData.at) lastNewDropsAtRef.current = newDropsData.at;
          // Only add to notifications when we sent since= (real-time "new since last poll"); first poll we just set baseline, add 0
          const isFirstPoll = !sinceParam;
          const MAX_NEW_PER_POLL = 25;
          const rawDrops = isFirstPoll ? [] : (Array.isArray(newDropsData.drops) ? newDropsData.drops.slice(0, MAX_NEW_PER_POLL) : []);
          if (newDropsRes.ok && rawDrops.length > 0 && Date.now() >= muteToastsUntilRef.current) {
            const dropsToConsider = rawDrops;
            const TOAST_TTL_MS = 7000;
            const seen = newDropsSeenIdsRef.current;
            const MAX_SEEN = 300;
            const newNotificationItems = [];
            setToasts((prev) => {
              const next = [...prev];
              const prevIds = new Set(prev.map((t) => t.drop.id));
              for (const d of dropsToConsider) {
                if (seen.has(d.id) || prevIds.has(d.id)) continue;
                const drop = {
                  ...d,
                  resyUrl: d.resy_url ?? d.resyUrl ?? (d.slots?.[0]?.resyUrl) ?? "#",
                  is_hotspot: !!d.is_hotspot,
                };
                if (d.slots?.[0] && !drop.slots[0].resyUrl) drop.slots[0].resyUrl = drop.resyUrl;
                const id = `toast-${d.id}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
                next.push({ id, drop });
                newNotificationItems.push({ id, drop, read: false, createdAt: Date.now() });
                // Special notify for NYC hotspots: browser notification when a hotspot becomes available
                if (drop.is_hotspot && typeof Notification !== "undefined" && Notification.permission === "granted") {
                  try {
                    new Notification("Hot spot available", {
                      body: `${drop.name || "Restaurant"} — new slot`,
                      icon: "/profile.png",
                      tag: `hotspot-${d.id}`,
                    });
                  } catch (_) { /* ignore */ }
                }
                prevIds.add(d.id);
                seen.add(d.id);
                const timeoutId = setTimeout(() => {
                  setToasts((p) => p.filter((t) => t.id !== id));
                  if (toastTimeoutsRef.current[id]) delete toastTimeoutsRef.current[id];
                }, TOAST_TTL_MS);
                toastTimeoutsRef.current[id] = timeoutId;
              }
              if (seen.size > MAX_SEEN) {
                const arr = [...seen];
                arr.slice(0, seen.size - MAX_SEEN).forEach((x) => seen.delete(x));
              }
              return next.slice(-8);
            });
            if (newNotificationItems.length > 0) {
              setNotifications((prev) => [...newNotificationItems, ...prev].slice(0, 50));
            }
          }
        } catch (_) {
          // non-fatal
        }
      } else {
        setJustOpenedError("Couldn't load feed. Is the backend running on port 8000?");
      }
    } catch (e) {
      const msg = e?.name === "AbortError" ? "Backend timed out. Is it running?" : "Couldn't reach backend. Start it with: make dev-backend";
      setJustOpenedError(msg);
    }
  }, [selectedTimes, selectedPartySizes, selectedDates, timeRangeStart, timeRangeEnd]);


  useEffect(() => {
    fetchJustOpened();
    const t = setInterval(fetchJustOpened, 15000);
    const onVisible = () => fetchJustOpened();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [fetchJustOpened]);

  // Track scroll position (for ticker vs pill and insert animation)
  useEffect(() => {
    const scrollContainer = newDropsSectionRef.current;
    if (!scrollContainer) return;
    const check = () => {
      const top = scrollContainer.scrollTop;
      isUserScrolledRef.current = top > 100;
      setIsNearTop(top <= 120);
    };
    scrollContainer.addEventListener("scroll", check);
    check();
    return () => scrollContainer.removeEventListener("scroll", check);
  }, []);
  
  // Handler: scroll to new drops and dismiss banner (no sidebar — toasts are signal bursts only)
  const handleScrollToNewDrops = useCallback(() => {
    if (alertDismissTimeoutRef.current) {
      clearTimeout(alertDismissTimeoutRef.current);
      alertDismissTimeoutRef.current = null;
    }
    setShowNewDropsBanner(false);
    setNewDropsCount(0);
    setNewDropsList([]);
    setNewDropsBannerLabel("");
    setNewDropsByDate(prev => {
      const updated = { ...prev };
      Array.from(selectedDates).forEach(date => {
        delete updated[date];
      });
      return updated;
    });
    requestAnimationFrame(() => {
      if (newDropsSectionRef.current) {
        newDropsSectionRef.current.scrollTo({ top: 0, behavior: "smooth" });
      }
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }, [selectedDates]);


  /** All drops for this request: from backend feed when present, else built from just_opened */
  const newDropsAll = useMemo(() => {
    if (apiFeed && Array.isArray(apiFeed.ranked_board)) return apiFeed.ranked_board;
    const discoveryDrops = buildDiscoveryDrops(justOpened, "Anytime");
    const fromToday = discoveryDrops.filter((d) => d.date_str && d.date_str >= todayStr);
    fromToday.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
    return fromToday;
  }, [apiFeed, justOpened, todayStr]);

  // Generate next 14 days for date filter with density (from calendar-counts API when available)
  const dateOptions = useMemo(() => {
    const options = [];
    const densityMap = new Map();
    newDropsAll.forEach(drop => {
      const count = densityMap.get(drop.date_str) || 0;
      densityMap.set(drop.date_str, count + 1);
    });

    const toLocalDateStr = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    for (let i = 0; i < 14; i++) {
      const d = new Date();
      d.setDate(d.getDate() + i);
      const dateStr = toLocalDateStr(d);
      const dayName = d.toLocaleDateString("en-US", { weekday: "short" }).toUpperCase();
      const dayNum = d.getDate();
      const monthName = d.toLocaleDateString("en-US", { month: "short" }).toUpperCase();
      // Use calendar-counts (just_opened + still_open per date) for bar graph when available
      const density = typeof calendarCounts.by_date[dateStr] === "number"
        ? calendarCounts.by_date[dateStr]
        : (densityMap.get(dateStr) || 0);
      
      options.push({ 
        key: dateStr, 
        label: i === 0 ? "Today" : i === 1 ? "Tomorrow" : dayName, 
        date: dateStr,
        dayNum,
        monthName,
        dayName,
        density
      });
    }
    return options;
  }, [todayStr, newDropsAll, calendarCounts.by_date]);

  // Filter drops: when backend sends feed it's already filtered; otherwise apply time + party client-side
  const filteredDrops = useMemo(() => {
    if (apiFeed && Array.isArray(apiFeed.ranked_board)) return apiFeed.ranked_board;
    let filtered = newDropsAll;

    // Time filter - if "all" is selected, show everything
    if (!selectedTimes.has("all")) {
      filtered = filtered.filter(d => {
        if (!d.time) return selectedTimes.has("all"); // If no time, only show if "all" is selected
        
        // Parse the hour from the time string (e.g., "7:30pm" -> 19, "2:15pm" -> 14)
        const timeStr = d.time.trim();
        const match = timeStr.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm|AM|PM)?/);
        if (!match) return false;
        
        let hour = parseInt(match[1], 10);
        const isPM = match[3] && match[3].toLowerCase() === 'pm';
        const isAM = match[3] && match[3].toLowerCase() === 'am';
        
        // Convert to 24-hour format
        if (isPM && hour !== 12) hour += 12;
        if (isAM && hour === 12) hour = 0;
        
        // Check against selected time filters (dinner uses configurable time range)
        if (selectedTimes.has("lunch") && hour >= 11 && hour < 15) return true;
        if (selectedTimes.has("3pm") && hour >= 15 && hour < 18) return true;
        if (selectedTimes.has("dinner")) {
          const [startH, startM] = timeRangeStart.split(":").map(Number);
          const [endH, endM] = timeRangeEnd.split(":").map(Number);
          const minStart = startH * 60 + (startM || 0);
          const minEnd = endH * 60 + (endM || 0);
          const dropMins = hour * 60 + (parseInt(match[2], 10) || 0);
          if (minEnd > minStart && dropMins >= minStart && dropMins < minEnd) return true;
          if (minEnd <= minStart && (dropMins >= minStart || dropMins < minEnd)) return true; // overnight
        }
        
        return false;
      });
    }

    // Party size filter - only show drops that have at least one selected party size
    if (selectedPartySizes.size > 0 && selectedPartySizes.size < 4) {
      filtered = filtered.filter(d => {
        const available = d.party_sizes_available || [];
        if (available.length === 0) return false; // No party size info
        return available.some(size => selectedPartySizes.has(size));
      });
    }

    return filtered;
  }, [apiFeed, newDropsAll, selectedTimes, selectedPartySizes, timeRangeStart, timeRangeEnd]);

  // Detect new drops and show notifications/banner (use all-dates list so notifications appear for any date)
  const dropsForNotifications = notificationDropsAllDates.length > 0 ? notificationDropsAllDates : newDropsAll;
  /** Drops created in the last N seconds count as "just appeared" so we notify even on first load */
  const NOTIFY_FRESH_SECONDS = 90;
  useEffect(() => {
    if (dropsForNotifications.length === 0) {
      setShowNewDropsBanner(false);
      return;
    }

    const currentDropIds = new Set(dropsForNotifications.map(d => d.id));
    let newIds = [...currentDropIds].filter(id => !seenDropIds.has(id));

    if (seenDropIds.size === 0) {
      // First load: only notify for drops that are truly fresh (created in last NOTIFY_FRESH_SECONDS)
      const nowMs = Date.now();
      const freshIds = new Set(
        dropsForNotifications
          .filter((d) => {
            const at = d.created_at ?? d.detected_at;
            if (!at) return false;
            const ms = new Date(at).getTime();
            return !Number.isNaN(ms) && nowMs - ms <= NOTIFY_FRESH_SECONDS * 1000;
          })
          .map((d) => d.id)
      );
      newIds = freshIds.size > 0 ? [...freshIds] : [];
      if (newIds.length === 0) {
        setSeenDropIds(currentDropIds);
        setShowNewDropsBanner(false);
        return;
      }
    }

    // No new drops this run → clear banner and list so it doesn't stay forever
    if (newIds.length === 0) {
      setShowNewDropsBanner(false);
      setNewDropsList([]);
      return;
    }

    // Count new drops by date: unique restaurants only (same restaurant with multiple spots = 1)
    const newByDate = {};
    const newDrops = dropsForNotifications.filter(d => newIds.includes(d.id));
    newDrops.forEach(drop => {
      const date = drop.date_str || todayStr;
      const key = drop.venueKey ?? drop.name ?? drop.id ?? "";
      if (!newByDate[date]) newByDate[date] = new Set();
      newByDate[date].add(key);
    });
    const newByDateCounts = {};
    Object.keys(newByDate).forEach(date => {
      newByDateCounts[date] = newByDate[date].size;
    });
    
    const selectedDateStrs = Array.from(selectedDates);

    // Update new drops count by date for badges (unique restaurants per date)
    setNewDropsByDate(prev => {
      const updated = { ...prev };
      Object.keys(newByDateCounts).forEach(date => {
        updated[date] = (updated[date] || 0) + newByDateCounts[date];
      });
      return updated;
    });
    
    const totalNewUnique = Object.values(newByDateCounts).reduce((a, b) => a + b, 0);

    const now = Date.now();

    // Notification: any new restaurant added, any date — show banner once, then auto-dismiss
    const ALERT_AUTO_DISMISS_MS = 8000;
    if (newDrops.length > 0) {
      if (alertDismissTimeoutRef.current) clearTimeout(alertDismissTimeoutRef.current);
      const uniqueAll = new Set();
      newDrops.forEach(d => uniqueAll.add(d.venueKey ?? d.name ?? d.id ?? ""));
      setNewDropsCount(uniqueAll.size);
      setNewDropsList(newDrops);
      setShowNewDropsBanner(true);
      const first = newDrops[0];
      const timeStr = first?.time ? formatTimeForSlot(first.time) : (first?.slots?.[0]?.time ? formatTimeForSlot(first.slots[0].time) : null);
      const dateStr = first?.date_str || first?.slots?.[0]?.date_str;
      const dateLabel = dateStr ? `${formatDayShort(dateStr)} ${formatMonthDay(dateStr)}` : "";
      const label = first
        ? timeStr
          ? dateLabel
            ? `${first.name} · ${dateLabel} · ${timeStr}`
            : `${first.name} · ${timeStr}`
          : `${first.name} — just opened`
        : "";
      setNewDropsBannerLabel(label || (first?.name ? `${first.name} — new slot available` : ""));
      setNewDropsBannerImageUrl(first?.image_url || "");
      alertDismissTimeoutRef.current = setTimeout(() => {
        setShowNewDropsBanner(false);
        alertDismissTimeoutRef.current = null;
      }, ALERT_AUTO_DISMISS_MS);
    }

    if (totalNewUnique > 0) {
      // First-seen for NEW badge + glow (~90s)
      newIds.forEach((id) => {
        if (!newCardFirstSeenAt.current[id]) newCardFirstSeenAt.current[id] = now;
      });
      setRankTick((t) => t + 1);

      // Top-right toasts are driven by GET /chat/watches/new-drops (all buckets), not here.

      // Browser notification: when tab is in background or user has alerts on (so they get notified even if not looking)
      if (newDrops.length > 0 && typeof Notification !== "undefined") {
        const sendBrowserNotification = (title, body) => {
          try {
            new Notification(title, { body, icon: "/profile.png" });
          } catch (_) { /* ignore */ }
        };
        const first = newDrops[0];
        const restaurantNames = [...new Set(newDrops.map((d) => d.name || "").filter(Boolean))];
        let title = "New restaurant added";
        let body;
        if (restaurantNames.length === 1) {
          const name = restaurantNames[0];
          const timeStr = first?.time ? formatTimeForSlot(first.time) : (first?.slots?.[0]?.time ? formatTimeForSlot(first.slots[0].time) : null);
          const dateStr = first?.date_str || first?.slots?.[0]?.date_str;
          const dateLabel = dateStr ? `${formatDayShort(dateStr)} ${formatMonthDay(dateStr)}` : "";
          body = timeStr && dateLabel ? `${name} · ${dateLabel} · ${timeStr}` : `${name} — table available`;
        } else {
          const dateParts = Object.entries(
            newDrops.reduce((acc, d) => {
              const date = d.date_str || todayStr;
              acc[date] = (acc[date] || 0) + 1;
              return acc;
            }, {})
          )
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([d, n]) => `${n} on ${d}`)
            .slice(0, 3);
          body = dateParts.length > 0 ? dateParts.join(", ") : `${newDrops.length} new place${newDrops.length === 1 ? "" : "s"} found`;
          title = newDrops.length === 1 ? "New restaurant added" : `${newDrops.length} new restaurants added`;
        }
        if (Notification.permission === "granted") {
          sendBrowserNotification(title, body);
        } else if (Notification.permission === "default") {
          Notification.requestPermission().then((p) => {
            if (p === "granted") sendBrowserNotification(title, body);
          });
        }
      }

      // Other-day pill: drops on days not selected (within 14-day range)
      const dateOptionKeys = new Set(dateOptions.map((o) => o.key));
      const selectedDateStrsSet = new Set(selectedDateStrs);
      const otherDayDrops = newDrops.filter(
        (d) => !selectedDateStrsSet.has(d.date_str || todayStr) && dateOptionKeys.has(d.date_str || "")
      );
      if (otherDayDrops.length > 0) {
        setOtherDayHotCountByDate((prev) => {
          const next = { ...prev };
          otherDayDrops.forEach((d) => {
            const date = d.date_str || todayStr;
            next[date] = (next[date] || 0) + 1;
          });
          return next;
        });
      }
    }

    // Mark as seen
    setSeenDropIds(currentDropIds);

    return () => {
      if (alertDismissTimeoutRef.current) {
        clearTimeout(alertDismissTimeoutRef.current);
        alertDismissTimeoutRef.current = null;
      }
    };
  }, [notificationDropsAllDates, newDropsAll, seenDropIds, selectedDates, todayStr, allDropsAlerts, dateOptions]);

  /** Consolidate drops: one card per restaurant, all date/time slots in that card */
  const consolidateDrops = (drops) => {
    const byName = new Map();
    
    for (const drop of drops) {
      const key = drop.name?.trim() || "";
      if (!key) continue;
      
      const releaseAt = drop.created_at ?? drop.detected_at;
      if (!byName.has(key)) {
        byName.set(key, {
          ...drop,
          id: `consolidated-${key}`,
          slots: [{ date_str: drop.date_str, time: drop.time, resyUrl: drop.resyUrl }],
          party_sizes_all: [...(drop.party_sizes_available || [])],
          created_at_earliest: releaseAt,
        });
      } else {
        const existing = byName.get(key);
        const hasSlot = existing.slots.some(s => s.date_str === drop.date_str && s.time === drop.time);
        if (!hasSlot) {
          existing.slots.push({ date_str: drop.date_str, time: drop.time, resyUrl: drop.resyUrl });
        }
        (drop.party_sizes_available || []).forEach(ps => {
          if (!existing.party_sizes_all.includes(ps)) existing.party_sizes_all.push(ps);
        });
        if (releaseAt && (!existing.created_at_earliest || releaseAt < existing.created_at_earliest)) {
          existing.created_at_earliest = releaseAt;
        }
      }
    }
    
    return Array.from(byName.values()).map(drop => {
      // Sort slots by date then time (earliest first) so primary CTA is the soonest option
      const sortedSlots = [...(drop.slots || [])].sort((a, b) => {
        const d = (a.date_str || "").localeCompare(b.date_str || "");
        if (d !== 0) return d;
        return (a.time || "").localeCompare(b.time || "");
      });
      const detected_at = drop.created_at_earliest ?? drop.created_at ?? drop.detected_at;
      return {
        ...drop,
        slots: sortedSlots,
        created_at: detected_at,
        detected_at,
        party_sizes_available: drop.party_sizes_all.sort((a, b) => a - b),
        times: sortedSlots.map(s => s.time).filter(Boolean),
        resyUrl: sortedSlots[0]?.resyUrl || null,
        all_resy_urls: sortedSlots.map(s => s.resyUrl).filter(Boolean),
      };
    });
  };

  // Re-rank every 15s for stability — avoid jitter from constant reshuffling
  const [rankTick, setRankTick] = useState(0);
  // Time tick every 10s so time-ago labels update visibly
  const [timeTick, setTimeTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setRankTick((t) => t + 1), 15000);
    return () => clearInterval(id);
  }, []);
  useEffect(() => {
    const id = setInterval(() => setTimeTick((t) => t + 1), 10000);
    return () => clearInterval(id);
  }, []);

  /** Priority score: heat × availability × freshness × Resy popularity (rating/collections from backend). */
  const priorityScore = (d) => {
    const heat = isHotRestaurant(d.name) ? 2 : 1;
    const availability = (d.slots && d.slots.length > 0) ? 1 : 0.01;
    const minutesAgo = d.created_at ? (Date.now() - new Date(d.created_at).getTime()) / 60000 : 999;
    const freshness = 1 / (1 + minutesAgo / 30);
    const popularity = d.resy_popularity_score != null && typeof d.resy_popularity_score === "number" ? 0.5 + d.resy_popularity_score : 1;
    return heat * availability * freshness * popularity;
  };

  /** Ranked opportunity board: from backend when present, else computed client-side */
  const rankedBoard = useMemo(() => {
    if (apiFeed && Array.isArray(apiFeed.ranked_board)) return apiFeed.ranked_board;
    const hotFromFeed = [];
    const rest = [];
    for (const d of filteredDrops) {
      const isHot = isHotRestaurant(d.name);
      if (isHot) hotFromFeed.push(d);
      else rest.push(d);
    }
    const stillOpenDrops = buildDiscoveryDrops(stillOpen, "Anytime");
    const stillOpenHot = stillOpenDrops.filter((d) => isHotRestaurant(d.name));
    const stillOpenRest = stillOpenDrops.filter((d) => !isHotRestaurant(d.name));
    const hotConsolidated = consolidateDrops([...hotFromFeed, ...stillOpenHot]);
    const restConsolidated = consolidateDrops([...rest, ...stillOpenRest]);
    const tag = (list, isHot, isStillOpen) =>
      list.map((d) => ({ ...d, feedHot: isHot, feedStillOpen: isStillOpen }));
    const merged = [
      ...tag(hotConsolidated, true, false),
      ...tag(restConsolidated, false, true),
    ];
    return merged
      .map((d) => ({ ...d, _priority: priorityScore(d) }))
      .sort((a, b) => b._priority - a._priority);
  }, [apiFeed, filteredDrops, stillOpen, rankTick]);

  /** Hot items (for Top Opportunities + Hot Right Now) */
  const hotItems = useMemo(
    () => rankedBoard.filter((d) => d.feedHot).sort((a, b) => (b._priority || 0) - (a._priority || 0)),
    [rankedBoard]
  );
  const nonHotItems = useMemo(() => rankedBoard.filter((d) => !d.feedHot), [rankedBoard]);
  const TOP_OPPORTUNITIES_MAX = 4;
  const HOT_RIGHT_NOW_HOME_MAX = 12;
  const MIN_SECOND_ROW_CARDS = 8; // At least 2 rows (4 cards per row → 8 cards min)
  /** Top Opportunities: from backend when present, else computed client-side */
  const topOpportunities = useMemo(() => {
    if (apiFeed && Array.isArray(apiFeed.top_opportunities)) return apiFeed.top_opportunities;
    const priorityPicks = [];
    const usedIds = new Set();
    for (const priorityName of TOP_OPPORTUNITY_PRIORITY_NAMES) {
      const match = rankedBoard.find((d) => {
        if (!d.name || usedIds.has(d.id)) return false;
        const n = d.name.toLowerCase();
        const p = priorityName.toLowerCase();
        return n.includes(p) || p.includes(n);
      });
      if (match) {
        priorityPicks.push(match);
        usedIds.add(match.id);
      }
    }
    const seen = new Set(priorityPicks.map((d) => d.id));
    const restHot = hotItems.filter((d) => !seen.has(d.id));
    const restNonHot = nonHotItems.filter((d) => !seen.has(d.id));
    let list = [...priorityPicks];
    for (const d of restHot) {
      if (list.length >= TOP_OPPORTUNITIES_MAX) break;
      list.push(d);
    }
    for (const d of restNonHot) {
      if (list.length >= TOP_OPPORTUNITIES_MAX) break;
      list.push(d);
    }
    return list.slice(0, TOP_OPPORTUNITIES_MAX);
  }, [apiFeed, rankedBoard, hotItems, nonHotItems]);
  const topZoneIds = useMemo(() => new Set(topOpportunities.map((d) => d.id)), [topOpportunities]);
  const hotRightNowRest = useMemo(() => hotItems.slice(TOP_OPPORTUNITIES_MAX), [hotItems]);
  const hotRightNowForHome = useMemo(() => hotRightNowRest.slice(0, HOT_RIGHT_NOW_HOME_MAX), [hotRightNowRest]);
  /** Hot Right Now: from backend when present, else computed client-side (deduped, padded, brand-new first) */
  const HOT_RIGHT_NOW_COLS = 5;
  const BRAND_NEW_SECONDS = 300;
  const venueDedupeKey = (d) => (d.name ?? "").toString().trim().toLowerCase().replace(/\s+/g, " ") || (d.venueKey ?? d.id);
  const homeFeedSecondRow = useMemo(() => {
    if (apiFeed && Array.isArray(apiFeed.hot_right_now)) return apiFeed.hot_right_now;
    const seenKeys = new Set();
    const dedupe = (items) =>
      items.filter((d) => {
        const key = venueDedupeKey(d);
        if (seenKeys.has(key)) return false;
        seenKeys.add(key);
        return true;
      });
    let list = dedupe(hotRightNowForHome);
    if (list.length < MIN_SECOND_ROW_CARDS) {
      const need = MIN_SECOND_ROW_CARDS - list.length;
      const padding = nonHotItems
        .filter((d) => !topZoneIds.has(d.id) && !seenKeys.has(venueDedupeKey(d)))
        .slice(0, need);
      padding.forEach((d) => seenKeys.add(venueDedupeKey(d)));
      list = [...list, ...padding];
    }
    const targetLen = Math.max(MIN_SECOND_ROW_CARDS, Math.ceil(list.length / HOT_RIGHT_NOW_COLS) * HOT_RIGHT_NOW_COLS);
    if (list.length < targetLen) {
      const extra = nonHotItems
        .filter((d) => !topZoneIds.has(d.id) && !seenKeys.has(venueDedupeKey(d)))
        .slice(0, targetLen - list.length);
      list = [...list, ...extra];
    }
    const isBrandNew = (d) => d.detected_at && (Math.floor((Date.now() - new Date(d.detected_at).getTime()) / 1000) < BRAND_NEW_SECONDS);
    return [...list].sort((a, b) => {
      const aNew = isBrandNew(a);
      const bNew = isBrandNew(b);
      if (aNew && !bNew) return -1;
      if (!aNew && bNew) return 1;
      return 0;
    });
  }, [apiFeed, hotRightNowForHome, nonHotItems, topZoneIds]);

  /** Just Dropped = added in last 10 min, newest first; cap at 20 for live ticker */
  const JUST_DROPPED_SECONDS = 600;
  const JUST_DROPPED_RAIL_MAX = 20;
  const justDroppedZone = useMemo(() => {
    return rankedBoard
      .filter((d) => {
        if (topZoneIds.has(d.id)) return false;
        const sec = d.created_at ? Math.floor((Date.now() - new Date(d.created_at).getTime()) / 1000) : 999;
        return sec < JUST_DROPPED_SECONDS;
      })
      .sort((a, b) => {
        const aSec = a.created_at ? new Date(a.created_at).getTime() : 0;
        const bSec = b.created_at ? new Date(b.created_at).getTime() : 0;
        return bSec - aSec;
      })
      .slice(0, JUST_DROPPED_RAIL_MAX);
  }, [rankedBoard, topZoneIds, rankTick]);

  const justDroppedIds = useMemo(() => new Set(justDroppedZone.map((d) => d.id)), [justDroppedZone]);

  /** Rest = everything not in top zone (hot) or justDropped (grid never reorders) */
  const restBoard = useMemo(
    () =>
      rankedBoard
        .filter((d) => !topZoneIds.has(d.id) && !justDroppedIds.has(d.id))
        .sort((a, b) => (b._priority || 0) - (a._priority || 0)),
    [rankedBoard, topZoneIds, justDroppedIds]
  );

  // Alias for "Live: watching N slots" and other references
  const unifiedFeed = rankedBoard;

  /** All Drops view: same items sorted by newest release (detected_at / created_at desc) */
  const allDropsByNewest = useMemo(() => {
    return [...rankedBoard].sort((a, b) => {
      const aT = a.detected_at || a.created_at;
      const bT = b.detected_at || b.created_at;
      if (!aT && !bT) return 0;
      if (!aT) return 1;
      if (!bT) return -1;
      return new Date(bT).getTime() - new Date(aT).getTime();
    });
  }, [rankedBoard]);

  // Prune NEW badge first-seen after 90s
  useEffect(() => {
    const interval = setInterval(() => {
      const now = Date.now();
      const cutoff = now - NEW_BADGE_SECONDS * 1000;
      let changed = false;
      const cur = newCardFirstSeenAt.current;
      Object.keys(cur).forEach((id) => {
        if (cur[id] < cutoff) {
          delete cur[id];
          changed = true;
        }
      });
      if (changed) setRankTick((t) => t + 1);
    }, 10000);
    return () => clearInterval(interval);
  }, []);

  // Show red LIVE SCAN line when we have drops OR when backend has scanned recently (so it shows even with 0 drops after reset)
  const RECENT_SCAN_MS = 10 * 60 * 1000; // 10 minutes
  useEffect(() => {
  }, [newDropsAll.length, lastScanAt]);

  // Filter: single date selection only; clear calendar notification for this date (user saw it)
  const selectDate = (key) => {
    setSelectedDates(new Set([key]));
    setNewDropsByDate(prev => {
      const updated = { ...prev };
      delete updated[key];
      return updated;
    });
    setOtherDayHotCountByDate((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
    // Mark drops for this date as seen so they aren't counted as "new" again on next fetch
    setSeenDropIds(prev => {
      const idsForDate = new Set(newDropsAll.filter(d => (d.date_str || todayStr) === key).map(d => d.id));
      if (idsForDate.size === 0) return prev;
      const next = new Set(prev);
      idsForDate.forEach(id => next.add(id));
      return next;
    });
  };

  const toggleTime = (key) => {
    setSelectedTimes(prev => {
      const next = new Set(prev);
      if (key === "all") {
        return new Set(["all"]);
      }
      next.delete("all");
      if (next.has(key)) {
        next.delete(key);
        if (next.size === 0) return new Set(["all"]);
      } else {
        next.add(key);
      }
      return next;
    });
  };

  const togglePartySize = (size) => {
    setSelectedPartySizes(prev => {
      const next = new Set(prev);
      if (next.has(size)) {
        next.delete(size);
        if (next.size === 0) return new Set([2, 3, 4, 5]);
      } else {
        next.add(size);
      }
      return next;
    });
  };

  const dismissToast = (id) => {
    if (toastTimeoutsRef.current[id]) {
      clearTimeout(toastTimeoutsRef.current[id]);
      delete toastTimeoutsRef.current[id];
    }
    setToasts((prev) => prev.filter((t) => t.id !== id));
  };
  const muteToasts10m = () => {
    muteToastsUntilRef.current = Date.now() + 10 * 60 * 1000;
    Object.values(toastTimeoutsRef.current).forEach(clearTimeout);
    toastTimeoutsRef.current = {};
    setToasts([]);
  };
  const onToastClick = () => {
    handleScrollToNewDrops();
    setToasts([]);
    Object.values(toastTimeoutsRef.current).forEach(clearTimeout);
    toastTimeoutsRef.current = {};
  };

  const markNotificationRead = (id) => {
    setNotifications((prev) => prev.map((n) => (n.id === id ? { ...n, read: true } : n)));
  };
  const markAllNotificationsRead = () => {
    setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
  };
  const dismissNotification = (id) => {
    setNotifications((prev) => prev.filter((n) => n.id !== id));
  };
  const onNotificationClick = (n) => {
    markNotificationRead(n.id);
    handleScrollToNewDrops();
    setNotificationPanelOpen(false);
  };

  return (
    <div className="flex flex-col h-screen text-[var(--color-text-main)] antialiased overflow-hidden font-sans font-light">
      {/* Header — logo + subtle live state | clean profile. No heavy toggles. */}
      <header className="h-14 shrink-0 px-6 sm:px-8 md:px-10 border-b border-slate-200 bg-white flex items-center justify-between z-[60]">
        <div className="flex items-center gap-2 sm:gap-3 min-w-0">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-red-600 to-red-700 flex items-center justify-center text-white shrink-0 shadow-lg shadow-red-900/30 ring-1 ring-white/10">
            <Flame className="w-5 h-5" strokeWidth={2} />
          </div>
          <h1 className="text-[13px] sm:text-[15px] font-black tracking-tight text-slate-900 truncate">DROP FEED</h1>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <DropdownMenu open={notificationPanelOpen} onOpenChange={setNotificationPanelOpen}>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                className="relative p-2 rounded-full text-slate-600 hover:text-slate-900 hover:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-slate-300 focus:ring-offset-2"
                title="Notifications"
                aria-label="Notifications"
              >
                <Bell className="w-5 h-5" />
                {unreadCount > 0 && (
                  <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1 flex items-center justify-center rounded-full bg-red-500 text-white text-[10px] font-bold">
                    {unreadCount > 99 ? "99+" : unreadCount}
                  </span>
                )}
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-[320px] sm:w-[360px] max-h-[70vh] overflow-hidden flex flex-col p-0">
              <div className="px-3 py-2 border-b border-slate-200 bg-slate-50">
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <h3 className="text-[13px] font-semibold text-slate-900">Notifications</h3>
                    <p className="text-[11px] text-slate-500 mt-0.5">New drops — click to view in feed, or mark as read</p>
                  </div>
                  {unreadCount > 0 && (
                    <button
                      type="button"
                      onClick={markAllNotificationsRead}
                      className="shrink-0 text-[11px] font-medium text-slate-500 hover:text-slate-700"
                    >
                      Mark all read
                    </button>
                  )}
                </div>
                {typeof Notification !== "undefined" && notificationPermission !== "granted" && (
                  <button
                    type="button"
                    onClick={() => {
                      Notification.requestPermission().then((p) => setNotificationPermission(p));
                    }}
                    className="mt-2 text-[11px] font-medium text-amber-600 hover:text-amber-700"
                  >
                    Enable desktop alerts for hotspots
                  </button>
                )}
              </div>
              <div className="overflow-y-auto flex-1 min-h-0">
                {notifications.length === 0 ? (
                  <p className="px-4 py-6 text-[12px] text-slate-500 text-center">No notifications yet. New drops will appear here.</p>
                ) : (
                  <ul className="py-1">
                    {notifications.map((n) => {
                      const timeStr = n.drop.time ? formatTimeForSlot(n.drop.time) : (n.drop.slots?.[0]?.time ? formatTimeForSlot(n.drop.slots[0].time) : null);
                      const dateStr = n.drop.date_str ?? n.drop.slots?.[0]?.date_str;
                      const dateLabel = dateStr ? `${formatDayShort(dateStr)} ${formatMonthDay(dateStr)}` : "";
                      const resyUrl = n.drop.slots?.[0]?.resyUrl ?? n.drop.resyUrl ?? "#";
                      const placeName = n.drop.name || "Restaurant";
                      return (
                        <li
                          key={n.id}
                          className={`group border-b border-slate-100 last:border-0 ${!n.read ? "bg-red-50/50" : "bg-white"}`}
                        >
                          <div className="px-3 py-2.5 flex items-start gap-2">
                            <button
                              type="button"
                              onClick={() => onNotificationClick(n)}
                              className="flex-1 min-w-0 text-left"
                            >
                              <p className="text-[10px] font-medium uppercase tracking-wide">
                                {n.drop.is_hotspot ? (
                                  <span className="text-amber-600">Hot spot</span>
                                ) : (
                                  <span className="text-red-500">New drop</span>
                                )}
                              </p>
                              <p className="text-[13px] font-semibold text-slate-900 truncate">{placeName}</p>
                              <p className="text-[11px] text-slate-500">{[dateLabel, timeStr].filter(Boolean).join(" · ") || "New slot"}</p>
                            </button>
                            <div className="flex items-center gap-1 shrink-0">
                              <a
                                href={resyUrl}
                                target="_blank"
                                rel="noopener noreferrer"
                                onClick={(e) => e.stopPropagation()}
                                className="px-2.5 py-1.5 rounded-lg bg-red-600 text-white text-[11px] font-semibold hover:bg-red-700 transition-colors"
                              >
                                Reserve
                              </a>
                              {!n.read && (
                                <button
                                  type="button"
                                  onClick={(e) => { e.stopPropagation(); markNotificationRead(n.id); }}
                                  className="px-2 py-1 rounded text-[10px] text-slate-500 hover:text-slate-700 hover:bg-slate-100"
                                >
                                  Mark read
                                </button>
                              )}
                              <button
                                type="button"
                                onClick={(e) => { e.stopPropagation(); dismissNotification(n.id); }}
                                className="p-1 rounded text-slate-400 hover:text-slate-600 hover:bg-slate-100"
                                aria-label="Dismiss"
                              >
                                <X className="w-4 h-4" />
                              </button>
                            </div>
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </div>
            </DropdownMenuContent>
          </DropdownMenu>
          <button
            type="button"
            className="relative rounded-full focus:outline-none focus:ring-2 focus:ring-slate-300 focus:ring-offset-2"
            title="Profile"
            aria-label="Profile"
          >
            <img
              src="/profile.png"
              alt=""
              className="w-9 h-9 rounded-full object-cover shadow-md ring-1 ring-slate-900/5"
            />
          </button>
        </div>
      </header>

      <div className="flex flex-1 overflow-hidden min-h-0">
        {/* Side update rail: ephemeral ticker, not a feed — what just changed, disappears in ~25s */}
        <div className="fixed right-4 top-1/2 -translate-y-1/2 z-40 w-[200px] hidden md:flex flex-col gap-2 pointer-events-none">
          <div className="pointer-events-auto flex flex-col gap-2">
            <AnimatePresence mode="popLayout">
              {sideUpdates.map((u) => (
                <motion.div
                  key={u.id}
                  initial={{ opacity: 0, x: 16 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: 8 }}
                  transition={{ duration: 0.25 }}
                  className="rounded-lg bg-white/95 backdrop-blur-sm border border-slate-200/80 shadow-md px-2.5 py-2 flex items-start gap-2"
                >
                  <span className="h-1.5 w-1.5 rounded-full bg-red-500 shrink-0 mt-1.5 animate-pulse" />
                  <div className="min-w-0 flex-1">
                    <p className="text-[11px] text-slate-700 leading-tight">{u.message}</p>
                    <p className="text-[9px] text-slate-400 mt-0.5">Just now</p>
                  </div>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </div>

        {/* Only the red banner is shown for hot new drops — no bottom-left pill */}

        <main className="flex-1 min-w-0 flex flex-col overflow-hidden bg-white relative">
          {/* DESIGN SYSTEM — Dark red (primary) + Grey (secondary)
              Primary: red-800/700 — CTAs, hot badges, accents
              Secondary: slate-900/600/500 — Text, borders, backgrounds
          */}
          
          <div className="flex-1 overflow-y-auto min-h-0 flex flex-col relative" ref={newDropsSectionRef}>


            {/* One compact filter row: pill dropdowns */}
            <div className="sticky top-0 z-10 shrink-0 border-b border-slate-200 bg-white px-6 sm:px-8 md:px-10 py-2 flex flex-wrap items-center gap-2">
              {(() => {
                const TIME_OPTS = [
                  { key: "all", label: "All" },
                  { key: "lunch", label: "Lunch" },
                  { key: "3pm", label: "Afternoon" },
                  { key: "dinner", label: "Dinner" },
                ];
                const fmtTime = (t) => {
                  const [h, m] = t.split(":").map(Number);
                  if (h === 0) return "12:" + String(m || 0).padStart(2, "0") + " AM";
                  if (h < 12) return h + ":" + String(m || 0).padStart(2, "0") + " AM";
                  if (h === 12) return "12:" + String(m || 0).padStart(2, "0") + " PM";
                  return (h - 12) + ":" + String(m || 0).padStart(2, "0") + " PM";
                };
                const timeLabel = selectedTimes.has("all") || selectedTimes.size === 0
                  ? "All"
                  : selectedTimes.has("dinner") && selectedTimes.size === 1
                    ? `Dinner (${fmtTime(timeRangeStart)} – ${fmtTime(timeRangeEnd)})`
                    : TIME_OPTS.filter(o => selectedTimes.has(o.key)).map(o => o.label).join(", ") || "All";
                const guestList = Array.from(selectedPartySizes).sort((a, b) => a - b);
                const guestLabel = guestList.length === 0 ? "Guests" : guestList.length === 1 ? `${guestList[0]} guests` : `${guestList.join(", ")} guests`;
                const dateLabel = selectedDateStr ? `${formatDayShort(selectedDateStr)} ${formatMonthDay(selectedDateStr)}` : "Date";
                return (
                  <>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <button
                          type="button"
                          className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-slate-200 bg-white text-slate-800 text-[12px] font-semibold hover:bg-slate-50 transition-colors"
                        >
                          {timeLabel}
                          <ChevronDown className="w-3.5 h-3.5 text-slate-500 shrink-0" />
                        </button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="start" className="min-w-[200px]">
                        {TIME_OPTS.map((opt) => (
                          <DropdownMenuCheckboxItem
                            key={opt.key}
                            checked={selectedTimes.has(opt.key)}
                            onCheckedChange={() => toggleTime(opt.key)}
                          >
                            {opt.label}
                          </DropdownMenuCheckboxItem>
                        ))}
                        {(() => {
                          const SLIDER_MIN = 17 * 60;   // 5pm
                          const SLIDER_MAX = 24 * 60;   // midnight
                          const STEP = 30;
                          const startMins = Math.max(SLIDER_MIN, Math.min(SLIDER_MAX - STEP, timeToMins(timeRangeStart)));
                          const endMins = Math.max(SLIDER_MIN + STEP, Math.min(SLIDER_MAX, timeToMins(timeRangeEnd)));
                          return (
                            <div className="px-2 py-2 border-t border-slate-100 mt-1 flex flex-col gap-2" onClick={e => e.stopPropagation()}>
                              <span className="text-[11px] font-medium text-slate-500">Time range</span>
                              <div className="flex flex-wrap gap-1.5">
                                {[
                                  { start: "18:00", end: "20:00", label: "6–8 PM" },
                                  { start: "18:00", end: "21:00", label: "6–9 PM" },
                                  { start: "19:00", end: "21:00", label: "7–9 PM" },
                                  { start: "19:00", end: "22:00", label: "7–10 PM" },
                                ].map(({ start, end, label }) => (
                                  <button
                                    key={label}
                                    type="button"
                                    onClick={() => { setTimeRangeStart(start); setTimeRangeEnd(end); }}
                                    className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
                                      timeRangeStart === start && timeRangeEnd === end
                                        ? "bg-red-100 text-red-800 border border-red-200"
                                        : "bg-slate-100 text-slate-700 border border-transparent hover:bg-slate-200"
                                    }`}
                                  >
                                    {label}
                                  </button>
                                ))}
                              </div>
                              <div className="flex flex-col gap-1.5">
                                <div className="flex items-center justify-between gap-2">
                                  <span className="text-[11px] text-slate-500">From</span>
                                  <span className="text-xs font-medium text-slate-700">{fmtTime(minsToTime(startMins))}</span>
                                </div>
                                <input
                                  type="range"
                                  min={SLIDER_MIN}
                                  max={SLIDER_MAX - STEP}
                                  step={STEP}
                                  value={startMins}
                                  onChange={e => {
                                    const v = Number(e.target.value);
                                    setTimeRangeStart(minsToTime(v));
                                    if (timeToMins(timeRangeEnd) <= v) setTimeRangeEnd(minsToTime(Math.min(SLIDER_MAX, v + STEP)));
                                  }}
                                  className="w-full h-2 accent-red-600"
                                />
                                <div className="flex items-center justify-between gap-2">
                                  <span className="text-[11px] text-slate-500">To</span>
                                  <span className="text-xs font-medium text-slate-700">{fmtTime(minsToTime(endMins))}</span>
                                </div>
                                <input
                                  type="range"
                                  min={SLIDER_MIN + STEP}
                                  max={SLIDER_MAX}
                                  step={STEP}
                                  value={endMins}
                                  onChange={e => {
                                    const v = Number(e.target.value);
                                    setTimeRangeEnd(minsToTime(v));
                                    if (timeToMins(timeRangeStart) >= v) setTimeRangeStart(minsToTime(Math.max(SLIDER_MIN, v - STEP)));
                                  }}
                                  className="w-full h-2 accent-red-600"
                                />
                              </div>
                              <div className="flex items-center gap-2">
                                <input
                                  type="time"
                                  value={timeRangeStart}
                                  onChange={e => setTimeRangeStart(e.target.value)}
                                  className="flex-1 min-w-0 text-xs border border-slate-200 rounded px-2 py-1.5 bg-white"
                                />
                                <span className="text-slate-400 text-xs">to</span>
                                <input
                                  type="time"
                                  value={timeRangeEnd}
                                  onChange={e => setTimeRangeEnd(e.target.value)}
                                  className="flex-1 min-w-0 text-xs border border-slate-200 rounded px-2 py-1.5 bg-white"
                                />
                              </div>
                            </div>
                          );
                        })()}
                      </DropdownMenuContent>
                    </DropdownMenu>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <button
                          type="button"
                          className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-slate-200 bg-white text-slate-800 text-[12px] font-semibold hover:bg-slate-50 transition-colors"
                        >
                          {guestLabel}
                          <ChevronDown className="w-3.5 h-3.5 text-slate-500 shrink-0" />
                        </button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="start" className="min-w-[100px]">
                        {[2, 3, 4, 5].map((size) => (
                          <DropdownMenuCheckboxItem
                            key={size}
                            checked={selectedPartySizes.has(size)}
                            onCheckedChange={() => {
                              setSelectedPartySizes(prev => {
                                const next = new Set(prev);
                                if (next.has(size)) next.delete(size);
                                else next.add(size);
                                return next.size === 0 ? prev : next;
                              });
                            }}
                          >
                            {size} guests
                          </DropdownMenuCheckboxItem>
                        ))}
                      </DropdownMenuContent>
                    </DropdownMenu>
                    <button
                      type="button"
                      onClick={() => setDateDrawerOpen((o) => !o)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-50 text-slate-700 text-[12px] font-medium hover:bg-slate-100 transition-colors"
                    >
                      {dateLabel}
                      <ChevronDown className={`w-3.5 h-3.5 text-slate-400 shrink-0 transition-transform ${dateDrawerOpen ? "rotate-180" : ""}`} />
                    </button>
                  </>
                );
              })()}
            </div>

            {/* Date rail — slide-down panel (Airbnb-style), only when open */}
            <AnimatePresence>
              {dateDrawerOpen && (
                <motion.div
                  initial={{ height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: 0.2, ease: "easeOut" }}
                  className="shrink-0 border-b border-slate-200 bg-white overflow-hidden"
                >
                  <div className="overflow-x-auto overflow-y-hidden scrollbar-hide min-h-[56px] px-6 sm:px-8 md:px-10 py-2.5">
                    <div className="flex items-center gap-1.5 min-w-max">
                      {dateOptions.map((opt) => {
                        const isSelected = selectedDates.has(opt.key);
                        const dropCount = newDropsByDate[opt.key] ?? calendarCounts.by_date?.[opt.key] ?? 0;
                        const hasDrops = dropCount > 0;
                        return (
                          <button
                            key={opt.key}
                            type="button"
                            onClick={() => {
                              selectDate(opt.key);
                              setDateDrawerOpen(false);
                            }}
                            className={`relative shrink-0 px-3 py-2 rounded-lg transition-all text-left ${
                              isSelected
                                ? "bg-slate-100 text-slate-900 ring-1 ring-slate-200/80 shadow-sm"
                                : "bg-slate-50/80 text-slate-600 hover:bg-slate-100/80 hover:text-slate-800"
                            }`}
                          >
                            <div className="flex flex-col items-center gap-0">
                              <div className="text-[10px] font-medium uppercase tracking-wide text-slate-500">{opt.dayName.slice(0, 3)}</div>
                              <div className={`text-[11px] font-semibold ${isSelected ? "text-slate-900" : "text-slate-700"}`}>{opt.monthName.slice(0, 3)} {opt.dayNum}</div>
                              {hasDrops && (
                                <div className="mt-1 w-1 h-1 rounded-full bg-red-400/80" aria-hidden="true" title="Has availability" />
                              )}
                            </div>
                            {isSelected && (
                              <div className="absolute bottom-0 left-1/2 -translate-x-1/2 w-6 h-0.5 rounded-full bg-slate-400" aria-hidden="true" />
                            )}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            <div className="flex-1 px-6 sm:px-8 md:px-10 pt-8 sm:pt-8 pb-6 no-scrollbar relative">
            {/* New Drops notify - top-right below header */}
            <AnimatePresence>
              {showNewDropsBanner && (
                <motion.div
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: 20 }}
                  className="fixed top-[calc(3.5rem+0.75rem)] right-6 sm:right-8 md:right-10 z-50"
                >
                  <button
                    type="button"
                    onClick={handleScrollToNewDrops}
                    className="bg-red-700 text-white rounded-lg px-3 py-2.5 flex items-center gap-2 hover:bg-red-800 transition-all shadow-md group max-w-[min(90vw,420px)] text-left"
                  >
                    <div className="w-2 h-2 rounded-full bg-white animate-pulse shrink-0" />
                    <span className="text-[12px] font-bold min-w-0 break-words">
                      {newDropsBannerLabel || "New slot available"}
                    </span>
                    <span className="text-[10px] opacity-80 group-hover:opacity-100 shrink-0">View in feed ↑</span>
                  </button>
                </motion.div>
              )}
            </AnimatePresence>

            <div>


              {/* Drop Cards */}
              {unifiedFeed.length === 0 ? (
                <div className="space-y-4">
                  {justOpenedError ? (
                    <div className="bg-red-100/50 border border-red-300 rounded-lg p-12 text-center">
                      <p className="text-[13px] text-red-700 font-medium">{justOpenedError}</p>
                    </div>
                  ) : isThatsItForToday ? (
                    <div className="rounded-xl border border-slate-200 bg-slate-50 p-10 sm:p-12 text-center">
                      <p className="text-[15px] font-medium text-slate-700">
                        That&apos;s it for today… the odds anything will open is very low.
                      </p>
                      <p className="text-[13px] text-slate-500 mt-2">
                        Pick tomorrow or another day to see live drops.
                      </p>
                    </div>
                  ) : (
                    <>
                      {/* Scanning skeleton cards */}
                      <div className="flex flex-wrap gap-4">
                        {[1, 2, 3, 4, 5, 6].map((i) => (
                          <div key={`skeleton-empty-${i}`} className="bg-white rounded-lg overflow-hidden border border-slate-200 animate-pulse flex max-w-[350px]">
                            <div className="w-20 h-20 bg-slate-100 shrink-0"></div>
                            <div className="flex-1 p-2.5 flex flex-col justify-between">
                      <div className="space-y-1">
                                <div className="h-3 bg-slate-100 rounded w-3/4"></div>
                                <div className="h-2 bg-slate-100 rounded w-1/2"></div>
                      </div>
                              <div className="flex justify-between items-center">
                                <div className="flex items-center gap-2">
                                  <div className="h-2.5 bg-slate-100 rounded w-12"></div>
                                  <div className="h-2 bg-slate-100 rounded w-8"></div>
                    </div>
                                <div className="h-6 bg-slate-100 rounded w-16"></div>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                      
                      {/* Status message - minimal */}
                      {lastScanAt != null && totalVenuesScanned > 0 && (
                        <p className="text-center text-[11px] text-slate-400 mt-6">
                          Scout found {totalVenuesScanned} venues. New drops appear when tables open.
                        </p>
                      )}
                    </>
                  )}
                </div>
              ) : (
                <>
                  {/* After 11 PM on today: odds are very low */}
                  {isThatsItForToday && (
                    <div className="mb-4 rounded-lg border border-slate-200 bg-slate-100/80 px-4 py-2.5 text-center">
                      <p className="text-[12px] text-slate-600">
                        That&apos;s it for today… the odds anything new will open is very low.
                      </p>
                    </div>
                  )}

                  {viewMode === "all" ? (
                    /* All Drops = scanning/exploration: full list, dense, chronological */
                    <>
                      <div className="mb-6 flex items-center gap-4">
                        <button
                          type="button"
                          onClick={() => setViewMode("home")}
                          className="flex items-center gap-1.5 text-[13px] font-semibold text-slate-600 hover:text-slate-900"
                        >
                          ← Back to Feed
                        </button>
                      </div>
                      <h2 className="text-[18px] font-bold text-slate-900 mb-0.5">All Drops</h2>
                      <p className="text-[11px] text-slate-500 mb-4">Live feed across all dates.</p>
                      <div className="grid gap-5" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))" }}>
                        {allDropsByNewest.map((drop, idx) => {
                          const imageUrl = drop.image_url;
                          const secondsSinceDetected = drop.detected_at ? Math.floor((Date.now() - new Date(drop.detected_at).getTime()) / 1000) : 999;
                          const isHot = !!drop.feedHot;
                          const firstSeenR = newCardFirstSeenAt.current[drop.id];
                          const isNewR = (firstSeenR && (Date.now() - firstSeenR) < NEW_BADGE_SECONDS * 1000) || secondsSinceDetected < 300;
                          return (
                            <motion.div
                              key={drop.id}
                              initial={{ opacity: 0, y: 4 }}
                              animate={{ opacity: 1, y: 0 }}
                              transition={{ duration: 0.2, delay: Math.min(idx * 0.02, 0.2), ease: "easeOut" }}
                              className={`rounded-xl overflow-hidden border bg-white transition-shadow hover:shadow-md group flex flex-col w-full min-w-0 shadow-sm ${isNewR ? "border-red-300 ring-2 ring-red-400/30" : "border-slate-200"}`}
                            >
                              <div className="relative h-20 sm:h-24 bg-gradient-to-br from-slate-800 to-slate-900">
                                {imageUrl && (
                                  <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover opacity-60 group-hover:opacity-70 transition-opacity" />
                                )}
                                <div className="absolute inset-0 flex items-start justify-between p-2">
                                  <span className={`px-2 py-0.5 rounded-md text-white text-[9px] font-semibold inline-flex items-center gap-1 ${isNewR ? "bg-[#7a473d]" : isHot ? "bg-[#6b3d33]" : "bg-slate-600"}`}>
                                    {isNewR ? <Sparkles className="w-2.5 h-2.5 shrink-0" /> : isHot ? <Flame className="w-2.5 h-2.5 shrink-0" /> : <Zap className="w-2.5 h-2.5 shrink-0" />}
                                    {isNewR ? "New" : isHot ? "Hot" : "Trending"}
                                  </span>
                                  {getFreshnessLabel(drop.detected_at) && (
                                    <span className="px-2 py-0.5 rounded-md bg-white/20 text-white text-[9px] font-medium">{getFreshnessLabel(drop.detected_at)}</span>
                                  )}
                                </div>
                              </div>
                              <div className="p-3 flex flex-col gap-2">
                                <div>
                                  <h4 className="text-[15px] font-bold text-slate-900 truncate">{drop.name}</h4>
                                  <p className="text-[11px] text-slate-500 mt-0.5">{drop.location || "NYC"} · {formatPartySizeShort(drop.party_sizes_available)}</p>
                                </div>
                                <div className="flex flex-nowrap items-center gap-1.5 min-w-0">
                                  {drop.slots && drop.slots.length > 0 ? (
                                    (() => {
                                      const sameDateOnly = drop.slots.every(s => s.date_str === drop.slots[0].date_str);
                                      const expanded = expandedSlotCardIds.has(drop.id);
                                      const firstSlot = drop.slots[0];
                                      const hasMore = drop.slots.length > 1 && !expanded;
                                      if (expanded) {
                                        return (
                                          <>
                                            <button type="button" onClick={() => setExpandedSlotCardIds(prev => { const next = new Set(prev); next.delete(drop.id); return next; })} className="px-2.5 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-600 text-[12px] font-semibold hover:bg-slate-100 shrink-0">← Back</button>
                                            {drop.slots.map((slot, tIdx) => (
                                              <a key={`all-${drop.id}-${slot.date_str}-${slot.time}-${tIdx}`} href={slot.resyUrl || "#"} target="_blank" rel="noopener noreferrer" className="px-2.5 py-1.5 rounded-lg border border-slate-200 bg-white text-slate-700 text-[12px] font-semibold hover:bg-slate-50 transition-colors shrink-0">
                                                {formatSlotLabel(slot, sameDateOnly)}
                                              </a>
                                            ))}
                                          </>
                                        );
                                      }
                                      return (
                                        <>
                                          <a href={firstSlot.resyUrl || "#"} target="_blank" rel="noopener noreferrer" className="px-2.5 py-1.5 rounded-lg border border-slate-200 bg-white text-slate-700 text-[12px] font-semibold hover:bg-slate-50 transition-colors truncate min-w-0 shrink">
                                            {formatSlotLabel(firstSlot, sameDateOnly)}
                                          </a>
                                          {hasMore && (
                                            <button type="button" onClick={() => setExpandedSlotCardIds(prev => new Set(prev).add(drop.id))} className="px-2.5 py-1.5 rounded-lg border border-slate-200 bg-slate-50 text-slate-600 text-[12px] font-semibold hover:bg-slate-100 shrink-0" title={`View all ${drop.slots.length} times`}>
                                              +{drop.slots.length - 1}
                                            </button>
                                          )}
                                        </>
                                      );
                                    })()
                                  ) : (
                                    <span className="text-[11px] text-slate-400">No times</span>
                                  )}
                                </div>
                              </div>
                            </motion.div>
                          );
                        })}
                      </div>
                    </>
                  ) : (
                    <>
                  {/* Per-bucket scan status: above Top Opportunities */}
                  {bucketHealth.length > 0 && selectedDateStr && (() => {
                    const bucketsForSelected = bucketHealth.filter((b) => b.date_str === selectedDateStr);
                    if (bucketsForSelected.length === 0) return null;
                    const slotLabel = (ts) => (ts === "15:00" ? "3pm" : ts === "19:00" ? "7pm" : ts);
                    const line = bucketsForSelected.map((b) => `${slotLabel(b.time_slot)} ${formatScanAgo(b.last_scan_at)}`).join(" · ");
                    return (
                      <div className="mb-4 flex items-center gap-2 text-[11px] text-slate-500">
                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 shrink-0" aria-hidden="true" />
                        <span>Scanned: {line}</span>
                      </div>
                    );
                  })()}
                  {/* 1) TOP OPPORTUNITIES — premium dark spotlight, ranked by demand */}
                  {topOpportunities.length > 0 && (
                    <section className="mb-10 -mx-6 sm:-mx-8 md:-mx-10 px-6 sm:px-8 md:px-10">
                      <div className="rounded-2xl overflow-hidden spotlight-section p-6 sm:p-8 relative">
                        <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-red-500/30 to-transparent" aria-hidden />
                        <div className="relative flex items-start justify-between gap-4 mb-6">
                          <div className="flex items-center gap-3">
                            <span className="flex items-center justify-center w-10 h-10 rounded-xl bg-gradient-to-br from-red-600 to-red-700 text-white shrink-0 shadow-lg shadow-red-900/30 ring-1 ring-white/10">
                              <Flame className="w-5 h-5" strokeWidth={2} />
                            </span>
                            <div className="flex flex-col gap-0.5">
                              <h2 className="text-[15px] font-bold text-white uppercase tracking-wider">Top Opportunities</h2>
                              <p className="text-[11px] text-slate-400 font-medium normal-case tracking-normal">Ranked by demand · Currently available</p>
                            </div>
                          </div>
                          <span className="hidden sm:inline-flex items-center px-2.5 py-1 rounded-lg bg-white/5 text-white/70 text-[10px] font-semibold uppercase tracking-widest border border-white/10">
                            Featured
                          </span>
                        </div>
                        <div className="grid gap-5 sm:gap-6" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))" }}>
                          {topOpportunities.map((drop, idx) => {
                            const imageUrl = drop.image_url;
                            const firstSlot = drop.slots?.[0];
                            const sameDateOnly = drop.slots?.every(s => s.date_str === drop.slots?.[0]?.date_str);
                            const hasMoreSlots = drop.slots && drop.slots.length > 1;
                            const expanded = expandedSlotCardIds.has(drop.id);
                            const secondsSinceDetected = drop.detected_at ? Math.floor((Date.now() - new Date(drop.detected_at).getTime()) / 1000) : 999;
                            const firstSeen = newCardFirstSeenAt.current[drop.id];
                            const isNewOpp = (firstSeen && (Date.now() - firstSeen) < NEW_BADGE_SECONDS * 1000) || secondsSinceDetected < 300;
                            const isHot = !!drop.feedHot;
                            return (
                              <motion.div
                                key={drop.id}
                                initial={{ opacity: 0, y: 12 }}
                                animate={{ opacity: 1, y: 0 }}
                                transition={{ duration: 0.35, delay: idx * 0.07, ease: [0.25, 0.46, 0.45, 0.94] }}
                                className={`spotlight-card rounded-2xl overflow-hidden bg-slate-800/90 flex flex-col min-w-0 w-full group ${isNewOpp ? "border border-red-400/40 ring-1 ring-red-400/30 shadow-red-900/20" : "border border-white/10"}`}
                              >
                                <div className="relative h-52 sm:h-60 flex flex-col">
                                  {imageUrl && (
                                    <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover opacity-80 group-hover:opacity-90 transition-opacity duration-300" />
                                  )}
                                  <div className="absolute inset-0 bg-gradient-to-t from-slate-900/97 via-slate-900/30 to-transparent" />
                                  <div className="absolute inset-0 flex items-start justify-between p-3">
                                    {isNewOpp && (
                                      <span className="px-2 py-0.5 rounded-md text-white text-[9px] font-semibold inline-flex items-center gap-1 bg-[#7a473d]">
                                        <Sparkles className="w-2.5 h-2.5 shrink-0" />
                                        New
                                      </span>
                                    )}
                                    {getFreshnessLabel(drop.detected_at) && (
                                      <span className="px-2 py-0.5 rounded-md bg-white/20 text-white text-[9px] font-medium">{getFreshnessLabel(drop.detected_at)}</span>
                                    )}
                                  </div>
                                  <div className="relative mt-auto p-4 sm:p-5 pt-8">
                                    {!expanded && (
                                      <>
                                        <h4 className="text-[18px] sm:text-[20px] font-bold text-white truncate drop-shadow-sm">{drop.name}</h4>
                                        <p className="text-[12px] text-white/85 mt-0.5">
                                          {drop.location || "NYC"} · Usually hard to get
                                        </p>
                                      </>
                                    )}
                                    {!expanded && (
                                      <div className="flex flex-nowrap items-center gap-2 mt-3 min-w-0">
                                        {firstSlot ? (
                                          <a
                                            href={firstSlot.resyUrl || "#"}
                                            target="_blank"
                                            rel="noopener noreferrer"
                                            className="spotlight-cta inline-flex items-center justify-center min-w-[100px] px-4 py-2.5 rounded-xl bg-white text-slate-900 text-[13px] font-bold hover:bg-slate-100 transition-colors shadow-lg truncate"
                                          >
                                            {formatSlotLabel(firstSlot, sameDateOnly)}
                                          </a>
                                        ) : null}
                                        {hasMoreSlots && (
                                          <button
                                            type="button"
                                            onClick={() => setExpandedSlotCardIds(prev => new Set(prev).add(drop.id))}
                                            className="spotlight-cta inline-flex items-center justify-center px-3 py-2.5 rounded-xl bg-white/90 text-slate-600 text-[13px] font-bold hover:bg-white transition-colors shadow-lg shrink-0"
                                            title={`View all ${drop.slots.length} times`}
                                          >
                                            +{drop.slots.length - 1}
                                          </button>
                                        )}
                                      </div>
                                    )}
                                    {expanded && drop.slots && drop.slots.length > 0 && (
                                      <div className="flex flex-wrap items-center gap-2">
                                        <button
                                          type="button"
                                          onClick={() => setExpandedSlotCardIds(prev => { const next = new Set(prev); next.delete(drop.id); return next; })}
                                          className="text-[11px] font-semibold text-white/90 hover:text-white shrink-0"
                                        >
                                          ← Back
                                        </button>
                                        {drop.slots.map((slot, tIdx) => (
                                          <a key={`opp-${drop.id}-${slot.date_str}-${slot.time}-${tIdx}`} href={slot.resyUrl || "#"} target="_blank" rel="noopener noreferrer" className="spotlight-cta px-3 py-2 rounded-xl bg-white text-slate-900 text-[13px] font-bold hover:bg-slate-100 transition-colors shadow-lg">
                                            {formatSlotLabel(slot, sameDateOnly)}
                                          </a>
                                        ))}
                                      </div>
                                    )}
                                  </div>
                                </div>
                              </motion.div>
                            );
                          })}
                        </div>
                      </div>
                    </section>
                  )}

                  {/* HOT RIGHT NOW — at least 2 rows: row 1 = Top Opportunities, row 2 = hot + padded with rest so never only top opps */}
                  {homeFeedSecondRow.length > 0 && (
                    <section className="mb-8 -mx-6 sm:-mx-8 md:-mx-10 px-6 sm:px-8 md:px-10">
                      <div className="rounded-xl border-slate-200 bg-white px-5 sm:px-6">
                        <h2 className="flex items-center gap-3 text-[12px] font-semibold text-slate-600 uppercase tracking-widest mb-4">
                          <span className="flex items-center justify-center w-10 h-10 rounded-xl bg-gradient-to-br from-red-600 to-red-700 text-white shrink-0 shadow-lg shadow-red-900/30 ring-1 ring-white/10">
                            <Flame className="w-5 h-5" strokeWidth={2} />
                          </span>
                          <span className="flex flex-col gap-0.5">
                            <span>Hot Right Now</span>
                            <span className="text-[11px] text-slate-500 font-normal normal-case tracking-normal">High-demand restaurants that are still open for your selected date</span>
                          </span>
                        </h2>
                        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
                          {homeFeedSecondRow.map((drop, idx) => {
                            const imageUrl = drop.image_url;
                            const secondsSinceDetected = drop.detected_at ? Math.floor((Date.now() - new Date(drop.detected_at).getTime()) / 1000) : 999;
                            const firstSeen = newCardFirstSeenAt.current[drop.id];
                            const isNew = (firstSeen && (Date.now() - firstSeen) < NEW_BADGE_SECONDS * 1000) || secondsSinceDetected < 300;
                            const isHot = !!drop.feedHot;
                            return (
                              <motion.div
                                key={drop.id}
                                initial={{ opacity: 0, y: 4 }}
                                animate={{ opacity: 1, y: 0 }}
                                transition={{ duration: 0.25, delay: Math.min(idx * 0.03, 0.3), ease: "easeOut" }}
                                className={`rounded-xl overflow-hidden bg-white border shadow-md hover:shadow-lg transition-shadow duration-200 group flex flex-col min-w-0 w-full ${isNew ? "border-red-300 ring-2 ring-red-400/40 shadow-red-900/10" : "border-slate-200"}`}
                              >
                                <div className="relative h-20 sm:h-24 bg-gradient-to-br from-slate-800 to-slate-900">
                                  {imageUrl && (
                                    <img src={imageUrl} alt="" className="absolute inset-0 w-full h-full object-cover opacity-60 group-hover:opacity-70 transition-opacity" />
                                  )}
                                  <div className="absolute inset-0 flex items-start justify-between p-2">
                                    {isNew && (
                                      <span className="px-2 py-0.5 rounded-md text-white text-[9px] font-semibold inline-flex items-center gap-1 shrink-0 bg-[#7a473d]">
                                        <Sparkles className="w-2.5 h-2.5 shrink-0" />
                                        New
                                      </span>
                                    )}
                                    {getFreshnessLabel(drop.detected_at) && (
                                      <span className="px-2 py-0.5 rounded-md bg-white/20 text-white text-[9px] font-medium shrink-0">{getFreshnessLabel(drop.detected_at)}</span>
                                    )}
                                  </div>
                                </div>
                                <div className="p-3 flex flex-col gap-2">
                                  <div>
                                    <h4 className="text-[14px] font-bold text-slate-900 truncate">{drop.name}</h4>
                                    <p className="text-[11px] text-slate-500 mt-0.5">
                                      {drop.location || "NYC"} · {formatPartySizeShort(drop.party_sizes_available)}
                                    </p>
                                  </div>
                                  <div className="flex flex-nowrap items-center gap-1.5 min-w-0">
                                    {drop.slots && drop.slots.length > 0 ? (
                                      (() => {
                                        const sameDateOnly = drop.slots.every(s => s.date_str === drop.slots[0].date_str);
                                        const expanded = expandedSlotCardIds.has(drop.id);
                                        const firstSlot = drop.slots[0];
                                        const hasMore = drop.slots.length > 1 && !expanded;
                                        if (expanded) {
                                          return (
                                            <>
                                              <button type="button" onClick={() => setExpandedSlotCardIds(prev => { const next = new Set(prev); next.delete(drop.id); return next; })} className="px-2.5 py-1.5 rounded-md border border-slate-200 bg-slate-50 text-slate-600 text-[12px] font-semibold hover:bg-slate-100 shrink-0">← Back</button>
                                              {drop.slots.map((slot, tIdx) => (
                                                <a key={`hrn-${drop.id}-${slot.date_str}-${slot.time}-${tIdx}`} href={slot.resyUrl || "#"} target="_blank" rel="noopener noreferrer" className="px-2.5 py-1.5 rounded-md border border-slate-200 bg-white text-slate-700 text-[12px] font-semibold hover:bg-slate-50 transition-colors shrink-0">
                                                  {formatSlotLabel(slot, sameDateOnly)}
                                                </a>
                                              ))}
                                            </>
                                          );
                                        }
                                        return (
                                          <>
                                            <a href={firstSlot.resyUrl || "#"} target="_blank" rel="noopener noreferrer" className="px-2.5 py-1.5 rounded-md border border-slate-200 bg-white text-slate-700 text-[12px] font-semibold hover:bg-slate-50 transition-colors truncate min-w-0 shrink">
                                              {formatSlotLabel(firstSlot, sameDateOnly)}
                                            </a>
                                            {hasMore && (
                                              <button type="button" onClick={() => setExpandedSlotCardIds(prev => new Set(prev).add(drop.id))} className="px-2.5 py-1.5 rounded-md border border-slate-200 bg-slate-50 text-slate-600 text-[12px] font-semibold hover:bg-slate-100 shrink-0" title={`View all ${drop.slots.length} times`}>
                                                +{drop.slots.length - 1}
                                              </button>
                                            )}
                                          </>
                                        );
                                      })()
                                    ) : (
                                      <span className="text-[11px] text-slate-400">No times</span>
                                    )}
                                  </div>
                                </div>
                              </motion.div>
                            );
                          })}
                        </div>
                      </div>
                    </section>
                  )}

                  {/* View all → dedicated All Drops page (no infinite list on home) */}
                  <div className="pt-8 pb-4 text-center">
                    <button
                      type="button"
                      onClick={() => {
                        setViewMode("all");
                        requestAnimationFrame(() => {
                          newDropsSectionRef.current?.scrollTo({ top: 0, behavior: "smooth" });
                        });
                      }}
                      className="inline-flex items-center gap-2 px-5 py-3 rounded-xl border-2 border-slate-200 bg-white text-slate-800 text-[14px] font-bold hover:border-slate-300 hover:bg-slate-50 transition-all"
                    >
                      View all available tables →
                    </button>
                    <p className="text-[11px] text-slate-500 mt-1.5">Live feed across all dates</p>
                  </div>
                </>
                  )}
                </>
              )}
            </div>

              <div className="min-h-0 mt-12" />
            </div>
          </div>

        </main>
      </div>

    </div>
  );
}

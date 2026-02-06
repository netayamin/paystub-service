import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { formatSessionDate } from "@/lib/formatTimes";
import { parseRestaurantListFromMessage } from "@/lib/parseRestaurantList";
import { motion, AnimatePresence } from "motion/react";
import { MessageWithVenueRatings } from "@/components/MessageWithVenueRatings";
import { RestaurantListSidebar } from "@/components/RestaurantListSidebar";
import { VenueListPlaceholder } from "@/components/VenueListPlaceholder";
import { WatchesTabs, JobsRunningSection } from "@/components/watches";
import {
  UtensilsCrossed,
  Zap,
  Send,
  Clock,
  ShieldCheck,
  Bell,
  ChevronDown,
  ArrowDownToLine,
  User,
  Plus,
} from "lucide-react";

const API_BASE = "";
const SESSION_STORAGE_KEY = "resy_chat_session_id";

function getStoredSessionId() {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(SESSION_STORAGE_KEY);
}

export default function App() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [sessionId, setSessionId] = useState(() => getStoredSessionId());
  const [sessions, setSessions] = useState([]);
  const [sessionsError, setSessionsError] = useState(null);
  const [messagesLoadError, setMessagesLoadError] = useState(null);
  const [watches, setWatches] = useState({ interval_watches: [], notify_requests: [], notifications: [] });
  const [expandedNotificationId, setExpandedNotificationId] = useState(null);
  const [availabilityByNotificationId, setAvailabilityByNotificationId] = useState({});
  const [loadingAvailabilityId, setLoadingAvailabilityId] = useState(null);
  const [countdownNow, setCountdownNow] = useState(() => Date.now());
  const [notificationPermission, setNotificationPermission] = useState(
    () => (typeof window !== "undefined" && "Notification" in window ? Notification.permission : "default")
  );
  const [bookingAttempts, setBookingAttempts] = useState([]);
  const [logEntries, setLogEntries] = useState([]);
  const abortRef = useRef(null);
  const prevNotificationIdsRef = useRef(new Set());
  const prevNotifiedRequestIdsRef = useRef(new Set());
  const watchesInitializedRef = useRef(false);
  const scrollContainerRef = useRef(null);
  const [showScrollToBottom, setShowScrollToBottom] = useState(false);
  const wasAtBottomRef = useRef(true);
  const [restaurantList, setRestaurantList] = useState(null);
  const streamVenueListRef = useRef(null);

  const scrollToBottom = useCallback((behavior = "smooth") => {
    const el = scrollContainerRef.current;
    if (!el) return;
    el.scrollTo({ top: el.scrollHeight, behavior });
    setShowScrollToBottom(false);
    wasAtBottomRef.current = true;
  }, []);

  const handleScroll = useCallback(() => {
    const el = scrollContainerRef.current;
    if (!el) return;
    const threshold = 80;
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < threshold;
    wasAtBottomRef.current = atBottom;
    setShowScrollToBottom((prev) => (atBottom ? false : true));
  }, []);

  useEffect(() => {
    const id = setInterval(() => setCountdownNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (messages.length === 0) return;
    const el = scrollContainerRef.current;
    if (!el) return;
    const atBottom = wasAtBottomRef.current;
    const lastIsStreaming = messages[messages.length - 1]?.role === "assistant" && messages[messages.length - 1]?.stream;
    if (atBottom || lastIsStreaming) {
      el.scrollTo({ top: el.scrollHeight, behavior: lastIsStreaming ? "auto" : "smooth" });
    }
  }, [messages.length, messages[messages?.length - 1]?.content]);

  // When last assistant message (non-streaming) has venue list, show list in sidebar.
  // Prefer API venueListItems (from stream); fallback to parsing message content. Do not clear if stream already set list.
  useEffect(() => {
    if (messages.length === 0) {
      setRestaurantList(null);
      return;
    }
    const lastIndex = messages.length - 1;
    const last = messages[lastIndex];
    if (last?.role !== "assistant" || last?.stream) return;
    // Prefer structured list from API (stream); never clear sidebar for this message when we have it
    if ((last.venueListItems?.length ?? 0) >= 1) {
      setRestaurantList((prev) => {
        if (prev?.messageIndex === lastIndex && (prev?.items?.length ?? 0) > 0) return prev;
        return { messageIndex: lastIndex, items: last.venueListItems, placeholderType: "venue_list" };
      });
      return;
    }
    const items = parseRestaurantListFromMessage(typeof last.content === "string" ? last.content : "");
    if (items.length >= 2) {
      setRestaurantList({
        messageIndex: lastIndex,
        items,
        placeholderType: "venue_list",
      });
    } else {
      setRestaurantList((prev) => {
        if (prev?.placeholderType === "venue_list") return prev;
        return null;
      });
    }
  }, [messages.length, messages[messages.length - 1]?.role, messages[messages.length - 1]?.stream, messages[messages.length - 1]?.content, messages[messages.length - 1]?.venueListItems]);

  const showBrowserNotification = useCallback((title, body, tag) => {
    if (typeof window === "undefined" || !("Notification" in window)) return;
    if (Notification.permission !== "granted") return;
    try {
      new Notification(title, { body, tag });
    } catch {
      // ignore
    }
  }, []);

  const fetchWatches = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/chat/watches`);
      if (res.ok) {
        const data = await res.json();
        const notifications = data.notifications || [];
        const notify_requests = data.notify_requests || [];

        if ("Notification" in window && Notification.permission === "default") {
          const perm = await Notification.requestPermission();
          setNotificationPermission(perm);
        } else if ("Notification" in window) {
          setNotificationPermission(Notification.permission);
        }

        const notificationIds = new Set(notifications.map((n) => n.id));
        const notifiedRequestIds = new Set(
          notify_requests.filter((r) => r.status === "notified").map((r) => r.id)
        );

        if (watchesInitializedRef.current) {
          for (const n of notifications) {
            if (!prevNotificationIdsRef.current.has(n.id)) {
              const names = (n.new_names || []).slice(0, 3).join(", ");
              const more =
                (n.new_names || []).length > 3
                  ? ` +${(n.new_names || []).length - 3} more`
                  : "";
              showBrowserNotification(
                "New venues available",
                `${n.criteria_summary || "New availability"}: ${names || "see app"}${more}`,
                `interval-${n.id}`
              );
            }
          }
          for (const r of notify_requests) {
            if (r.status === "notified" && !prevNotifiedRequestIdsRef.current.has(r.id)) {
              const times = (r.found_times || []).slice(0, 3).join(", ");
              const timeStr = times ? ` — ${times}` : "";
              showBrowserNotification(
                `${r.venue_name} has availability`,
                `${r.date_str || ""}${timeStr}`.trim() || "Check the app for times.",
                `notify-${r.id}`
              );
            }
          }
        } else {
          watchesInitializedRef.current = true;
        }
        prevNotificationIdsRef.current = notificationIds;
        prevNotifiedRequestIdsRef.current = notifiedRequestIds;

        setWatches({
          interval_watches: data.interval_watches || [],
          notify_requests,
          notifications,
        });
      }
    } catch {
      // ignore
    }
  }, [showBrowserNotification]);

  const loadMessagesForSession = useCallback(async (sid) => {
    if (!sid) return;
    setMessagesLoadError(null);
    try {
      const res = await fetch(`${API_BASE}/chat/messages?session_id=${encodeURIComponent(sid)}`);
      if (res.ok) {
        const data = await res.json();
        const loaded = (data.messages || []).map((m) => ({ ...m, stream: false }));
        setMessages(loaded);
        const lastIdx = loaded.length - 1;
        const lastIsAssistant = lastIdx >= 0 && loaded[lastIdx]?.role === "assistant";
        if (lastIsAssistant) {
          const venuesRes = await fetch(`${API_BASE}/chat/venues?session_id=${encodeURIComponent(sid)}`);
          const venuesData = await venuesRes.json().catch(() => ({}));
          const list = Array.isArray(venuesData.venues) ? venuesData.venues : [];
          if (list.length >= 1) {
            setMessages((prev) => {
              const next = [...prev];
              if (next[lastIdx]?.role === "assistant") next[lastIdx] = { ...next[lastIdx], venueListItems: list };
              return next;
            });
            setRestaurantList({ messageIndex: lastIdx, items: list, placeholderType: "venue_list" });
          }
        }
      } else {
        setMessages([]);
        setMessagesLoadError("Couldn't load this conversation.");
      }
    } catch {
      setMessages([]);
      setMessagesLoadError("Couldn't load this conversation.");
    }
  }, []);

  const fetchSessions = useCallback(async () => {
    setSessionsError(null);
    try {
      const res = await fetch(`${API_BASE}/chat/sessions?limit=20`);
      if (res.ok) {
        const data = await res.json();
        setSessions(data.sessions || []);
      } else {
        setSessions([]);
        setSessionsError("Couldn't load conversation history.");
      }
    } catch {
      setSessions([]);
      setSessionsError("Couldn't load conversation history.");
    }
  }, []);

  const fetchBookingErrors = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/chat/booking-errors`);
      if (res.ok) {
        const data = await res.json();
        setBookingAttempts(data.attempts || []);
      }
    } catch {
      // ignore
    }
  }, []);

  const fetchLogs = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/chat/logs`);
      if (res.ok) {
        const data = await res.json();
        setLogEntries(data.entries || []);
      }
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    fetchWatches();
    fetchBookingErrors();
    fetchLogs();
    const t = setInterval(() => {
      fetchWatches();
      fetchBookingErrors();
      fetchLogs();
    }, 30000);
    const onVisible = () => {
      fetchWatches();
      fetchBookingErrors();
      fetchLogs();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [fetchWatches, fetchBookingErrors, fetchLogs]);

  useEffect(() => {
    if (sessionId) loadMessagesForSession(sessionId);
    else {
      setMessages([]);
      setMessagesLoadError(null);
    }
  }, [sessionId, loadMessagesForSession]);

  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  const startNewConversation = () => {
    setSessionId(null);
    setMessages([]);
    setRestaurantList(null);
    try {
      localStorage.removeItem(SESSION_STORAGE_KEY);
    } catch {}
    fetchSessions();
  };

  const clearOldChats = async () => {
    if (!window.confirm("Delete all saved conversations? This cannot be undone.")) return;
    try {
      const res = await fetch(`${API_BASE}/chat/sessions/all`, { method: "DELETE" });
      if (res.ok) {
        startNewConversation();
      }
    } catch {
      // ignore
    }
  };

  const switchConversation = (sid) => {
    if (sid === sessionId) return;
    setMessages([]);
    setRestaurantList(null);
    setSessionId(sid);
    try {
      localStorage.setItem(SESSION_STORAGE_KEY, sid);
    } catch {}
    fetchWatches();
  };

  const cancelIntervalWatch = async (watchId) => {
    try {
      const res = await fetch(`${API_BASE}/chat/watches/interval/${watchId}`, { method: "DELETE" });
      if (res.ok) await fetchWatches();
    } catch {}
  };

  const cancelNotifyRequest = async (requestId) => {
    try {
      const res = await fetch(`${API_BASE}/chat/watches/notify/${requestId}`, { method: "DELETE" });
      if (res.ok) await fetchWatches();
    } catch {}
  };

  const markNotificationRead = async (notificationId) => {
    try {
      const res = await fetch(`${API_BASE}/chat/watches/notifications/${notificationId}/read`, { method: "POST" });
      if (res.ok) await fetchWatches();
    } catch {}
  };

  const clearAllNotifications = async () => {
    const notifications = watches.notifications || [];
    if (!notifications.length) return;
    try {
      await Promise.all(notifications.map((n) => fetch(`${API_BASE}/chat/watches/notifications/${n.id}/read`, { method: "POST" })));
      await fetchWatches();
    } catch {}
  };

  const fetchAvailabilityForNotification = useCallback(async (n) => {
    setLoadingAvailabilityId(n.id);
    try {
      const params = new URLSearchParams({
        date_str: n.date_str,
        party_size: String(n.party_size),
      });
      if (n.time_filter) params.set("time_filter", n.time_filter);
      const res = await fetch(`${API_BASE}/chat/watches/availability?${params.toString()}`);
      if (res.ok) {
        const data = await res.json();
        setAvailabilityByNotificationId((prev) => ({ ...prev, [n.id]: data.venues || [] }));
      }
    } catch {
      // ignore
    } finally {
      setLoadingAvailabilityId(null);
    }
  }, []);

  const sendMessage = async () => {
    const text = input.trim();
    if (!text || loading) return;

    setInput("");
    setMessages((prev) => [...prev, { role: "user", content: text }]);
    setLoading(true);

    const userMessage = text;
    let assistantContent = "";

    setMessages((prev) => [
      ...prev,
      { role: "assistant", content: "", stream: true },
    ]);

    const sentSessionId = sessionId;
    try {
      const res = await fetch(`${API_BASE}/chat/stream`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: userMessage,
          session_id: sentSessionId ?? undefined,
        }),
      });

      if (!res.ok) {
        const errBody = await res.text();
        let msg = res.statusText;
        try {
          const j = JSON.parse(errBody);
          if (j.error) msg = j.error;
        } catch (_) {}
        throw new Error(msg);
      }
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      abortRef.current = () => reader.cancel();

      let receivedSessionId = null;
      let buffer = "";
      const processEvent = (eventStr) => {
        if (!eventStr.startsWith("data: ")) return;
        try {
          const data = JSON.parse(eventStr.slice(6));
          if (data.content) {
            assistantContent += data.content;
            setMessages((prev) => {
              const next = [...prev];
              const last = next[next.length - 1];
              if (last?.role === "assistant" && last?.stream) {
                next[next.length - 1] = { ...last, content: assistantContent };
              }
              return next;
            });
          }
          if (Array.isArray(data.venues) && data.venues.length >= 1) {
            streamVenueListRef.current = data.venues;
            let lastIdxForSidebar = 0;
            setMessages((prev) => {
              const next = [...prev];
              lastIdxForSidebar = next.length - 1;
              if (lastIdxForSidebar >= 0 && next[lastIdxForSidebar]?.role === "assistant") {
                next[lastIdxForSidebar] = { ...next[lastIdxForSidebar], venueListItems: data.venues };
              }
              return next;
            });
            setRestaurantList({
              messageIndex: lastIdxForSidebar,
              items: data.venues,
              placeholderType: "venue_list",
            });
          }
          if (data.session_id) {
            receivedSessionId = data.session_id;
            setSessionId(data.session_id);
            try {
              localStorage.setItem(SESSION_STORAGE_KEY, data.session_id);
            } catch {}
            fetchSessions();
            fetchWatches();
          }
          if (data.error) throw new Error(data.error);
        } catch (e) {
          if (e instanceof SyntaxError) return;
          throw e;
        }
      };
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        while (buffer.includes("\n\n")) {
          const idx = buffer.indexOf("\n\n");
          const event = buffer.slice(0, idx).trim();
          buffer = buffer.slice(idx + 2);
          processEvent(event);
        }
      }
      while (buffer.includes("\n\n")) {
        const idx = buffer.indexOf("\n\n");
        const event = buffer.slice(0, idx).trim();
        buffer = buffer.slice(idx + 2);
        processEvent(event);
      }
      if (buffer.trim().startsWith("data: ")) processEvent(buffer.trim());

      setMessages((prev) => {
        const next = [...prev];
        const last = next[next.length - 1];
        if (last?.role === "assistant") {
          const venueList = last.venueListItems ?? streamVenueListRef.current;
          const content = (last.content ?? assistantContent) || "No response received.";
          next[next.length - 1] = {
            ...last,
            content,
            stream: false,
            ...(venueList?.length >= 1 && { venueListItems: venueList }),
          };
          streamVenueListRef.current = null;
        }
        return next;
      });
      const sidToRefetch = receivedSessionId ?? sentSessionId;
      if (sidToRefetch) {
        fetchWatches();
        fetchLogs();
        [400, 1000, 2500].forEach((ms) => setTimeout(() => { fetchWatches(); fetchLogs(); }, ms));
        // Fallback: if stream didn't attach venues, load from saved session search (same data as snapshot/compare)
        fetch(`${API_BASE}/chat/venues?session_id=${encodeURIComponent(sidToRefetch)}`)
          .then((res) => (res.ok ? res.json() : { venues: [] }))
          .then((data) => {
            const list = Array.isArray(data.venues) ? data.venues : [];
            if (list.length < 1) return;
            setMessages((prev) => {
              const next = [...prev];
              const lastIdx = next.length - 1;
              if (lastIdx >= 0 && next[lastIdx]?.role === "assistant" && (next[lastIdx].venueListItems?.length ?? 0) < 1) {
                next[lastIdx] = { ...next[lastIdx], venueListItems: list };
                setRestaurantList({ messageIndex: lastIdx, items: list, placeholderType: "venue_list" });
                return next;
              }
              return prev;
            });
          })
          .catch(() => {});
      }
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: `Error: ${err.message}`, stream: false },
      ]);
    } finally {
      setLoading(false);
      abortRef.current = null;
    }
  };

  return (
    <div className="flex flex-col h-screen w-full text-slate-900 antialiased bg-[var(--color-app-workspace-bg)]">
      {/* Top header: reference nav-bg, logo + Elite Concierge (conversations), profile */}
      <header className="h-16 bg-[var(--color-nav-bg)] flex items-center justify-between px-6 shrink-0 z-50">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-[var(--color-primary-accent)] rounded flex items-center justify-center text-white">
            <UtensilsCrossed className="w-4 h-4 text-white" />
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button type="button" className="text-white text-sm font-bold tracking-tight uppercase hover:opacity-90">
                Elite Concierge
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" side="bottom" sideOffset={4} className="min-w-[220px] z-[100]">
              <DropdownMenuItem onClick={startNewConversation} className="text-xs">
                New conversation
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuLabel className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                Conversation history
              </DropdownMenuLabel>
              {sessionsError ? (
                <div className="px-2 py-3 text-xs text-amber-600">{sessionsError}</div>
              ) : sessions.length === 0 ? (
                <div className="px-2 py-3 text-xs text-slate-500">No previous conversations yet.</div>
              ) : (
                <>
                  {sessions.slice(0, 20).map((s) => (
                    <DropdownMenuItem key={s.session_id} onClick={() => switchConversation(s.session_id)} className="text-xs">
                      <span className="font-mono text-slate-500">{formatSessionDate(s.updated_at)}</span>
                      <span className="ml-1 truncate text-slate-700">{s.session_id.slice(0, 8)}…</span>
                    </DropdownMenuItem>
                  ))}
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={clearOldChats} className="text-xs text-red-600 focus:text-red-600">
                    Clear all conversations
                  </DropdownMenuItem>
                </>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
        <div className="flex items-center gap-6">
          <div className="flex items-center gap-3 px-3 py-1.5 rounded-full bg-white/5 border border-white/10">
            <div className="w-6 h-6 rounded-full bg-slate-600 flex items-center justify-center shrink-0" aria-hidden>
              <User className="w-3.5 h-3.5 text-slate-300" />
            </div>
            <span className="text-xs font-medium text-slate-300">Neta Y</span>
            <ChevronDown className="w-4 h-4 text-slate-400" />
          </div>
        </div>
      </header>

      <div className="flex flex-1 overflow-hidden p-4 gap-4 min-h-0">
      {/* Left sidebar: section-card with Found Tables + Active Monitors + New Monitor */}
      <aside className="w-80 flex flex-col gap-4 shrink-0 min-h-0">
        <div className="section-card flex-1 flex flex-col min-h-0">
          <div className="flex flex-col flex-1 min-h-0">
            <div className="flex flex-col flex-1 min-h-0 border-b border-slate-100">
              <WatchesTabs
                theme="light"
                watches={watches}
                countdownNow={countdownNow}
                expandedNotificationId={expandedNotificationId}
                setExpandedNotificationId={setExpandedNotificationId}
                availabilityByNotificationId={availabilityByNotificationId}
                loadingAvailabilityId={loadingAvailabilityId}
                fetchAvailabilityForNotification={fetchAvailabilityForNotification}
                fetchWatches={fetchWatches}
                cancelIntervalWatch={cancelIntervalWatch}
                cancelNotifyRequest={cancelNotifyRequest}
                markNotificationRead={markNotificationRead}
                onClearAllNotifications={clearAllNotifications}
                notificationPermission={notificationPermission}
                logEntries={logEntries}
                fetchLogs={fetchLogs}
              />
            </div>
            <div className="flex flex-col min-h-0 flex-1 bg-white overflow-hidden">
              <JobsRunningSection
                variant="sidebar"
                intervalWatches={watches.interval_watches}
                notifyRequests={watches.notify_requests}
                onCancelWatch={cancelIntervalWatch}
                onCancelRequest={cancelNotifyRequest}
              />
              <button
                type="button"
                className="w-full py-4 border-t border-slate-100 text-[10px] font-bold uppercase tracking-widest hover:bg-orange-50 transition-colors flex items-center justify-center gap-2 text-[var(--color-primary-accent)]"
              >
                <Plus className="w-4 h-4" />
                New Monitor
              </button>
            </div>
          </div>
        </div>
      </aside>

      {/* Main + optional restaurant list sidebar (pushes chat when open) */}
      <div className="flex min-h-0 min-w-0 flex-1 gap-4 overflow-hidden">
        <motion.main
          layout
          transition={{ type: "tween", duration: 0.35, ease: [0.32, 0.72, 0, 1] }}
          className="flex-1 flex flex-col min-w-0 min-h-0"
        >
        <section className="section-card flex-1 flex flex-col min-h-0">
        <div
          ref={scrollContainerRef}
          onScroll={handleScroll}
          className="flex-1 overflow-y-auto no-scrollbar min-h-0 p-8"
        >
          <div className="flex min-h-full flex-col mx-auto space-y-10">
            {messagesLoadError ? (
              <div className="flex max-w-3xl flex-col items-center justify-center py-12 w-full">
                <p className="text-sm text-amber-600 dark:text-amber-500">{messagesLoadError}</p>
                <Button variant="outline" size="sm" className="mt-4" onClick={() => loadMessagesForSession(sessionId)}>
                  Try again
                </Button>
              </div>
            ) : messages.length === 0 ? (
              <div className="flex max-w-3xl flex-col items-center space-y-12 w-full">
                <div className="space-y-4 text-center">
                  <div className="inline-flex h-16 w-16 items-center justify-center rounded-sm bg-brand-black text-white shadow-xl mb-2">
                    <Zap className="h-8 w-8" />
                  </div>
                  <h2 className="font-display text-3xl font-light tracking-tight text-brand-black">
                    Instant Alerts, Zero Effort.
                  </h2>
                  <p className="mx-auto max-w-lg text-sm leading-relaxed text-stone-500">
                    Your Concierge agent doesn&apos;t just watch the clock—it strikes the second a table opens. From cancellations to surprise availability, we notify and book before anyone else.
                  </p>
                </div>
                <div className="grid w-full max-w-2xl grid-cols-1 gap-3 md:grid-cols-2">
                  <button
                    type="button"
                    onClick={() => setInput('Watch for any cancellations at Polo Bar for 4 tonight.')}
                    className="group rounded-sm border border-border-subtle bg-white p-5 text-left transition-all duration-200 hover:border-brand-black hover:-translate-y-0.5 hover:shadow"
                  >
                    <div className="flex items-start justify-between">
                      <div className="space-y-1">
                        <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Immediate Watch</span>
                        <p className="text-sm font-medium text-slate-800">&quot;Watch for any cancellations at Polo Bar for 4 tonight.&quot;</p>
                      </div>
                      <Bell className="h-5 w-5 text-stone-300 transition-colors group-hover:text-brand-black" />
                    </div>
                  </button>
                  <button
                    type="button"
                    onClick={() => setInput('Notify me the instant a prime slot opens at I Sodi.')}
                    className="group rounded-sm border border-border-subtle bg-white p-5 text-left transition-all duration-200 hover:border-brand-black hover:-translate-y-0.5 hover:shadow"
                  >
                    <div className="flex items-start justify-between">
                      <div className="space-y-1">
                        <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Automated Search</span>
                        <p className="text-sm font-medium text-slate-800">&quot;Notify me the instant a prime slot opens at I Sodi.&quot;</p>
                      </div>
                      <Zap className="h-5 w-5 text-stone-300 transition-colors group-hover:text-brand-black" />
                    </div>
                  </button>
                </div>
              </div>
            ) : (
              <div className="w-full space-y-6">
                {messages.map((m, i) => {
                  const hasVenueList = (m.venueListItems?.length ?? 0) >= 1;
                  const mentionsSidebar = m.role === "assistant" && /real-time inventory|sidebar/i.test((m.content || "").trim());
                  const showSidebarPlaceholder = hasVenueList || mentionsSidebar;
                  const sidebarItems = m.venueListItems ?? [];
                  return (
                  <div
                    key={i}
                    className={m.role === "user" ? "flex flex-col items-end gap-2" : "flex flex-col items-start gap-2"}
                  >
                    {m.role === "user" && (
                      <div className="flex items-center gap-2">
                        <span className="text-[10px] font-bold text-slate-400 uppercase">You</span>
                        <div className="w-5 h-5 rounded-full bg-slate-200 flex items-center justify-center shrink-0" aria-hidden>
                          <User className="w-3 h-3 text-slate-500" />
                        </div>
                      </div>
                    )}
                    {m.role === "assistant" && (
                      <div className="flex items-center gap-2">
                        <div className="w-5 h-5 rounded bg-[var(--color-nav-bg)] flex items-center justify-center shrink-0">
                          <Zap className="w-3 h-3 text-white" />
                        </div>
                        <span className="text-[10px] font-bold text-slate-400 uppercase">Concierge AI</span>
                      </div>
                    )}
                    <div className={m.role === "user" ? "max-w-[80%]" : "max-w-[85%] space-y-4"}>
                      <div
                        role={m.role === "assistant" && showSidebarPlaceholder ? "button" : undefined}
                        tabIndex={m.role === "assistant" && showSidebarPlaceholder ? 0 : undefined}
                        onClick={
                          m.role === "assistant" && showSidebarPlaceholder
                            ? (e) => {
                                e.preventDefault();
                                e.stopPropagation();
                                setRestaurantList((prev) => {
                                  const items = sidebarItems.length > 0 ? sidebarItems : (prev?.messageIndex === i && (prev?.items?.length ?? 0) > 0 ? prev.items : []);
                                  return { messageIndex: i, items, placeholderType: "venue_list" };
                                });
                              }
                            : undefined
                        }
                        onKeyDown={
                          m.role === "assistant" && showSidebarPlaceholder
                            ? (e) => {
                                if (e.key === "Enter" || e.key === " ") {
                                  e.preventDefault();
                                  setRestaurantList((prev) => {
                                    const items = sidebarItems.length > 0 ? sidebarItems : (prev?.messageIndex === i && (prev?.items?.length ?? 0) > 0 ? prev.items : []);
                                    return { messageIndex: i, items, placeholderType: "venue_list" };
                                  });
                                }
                              }
                            : undefined
                        }
                        data-placeholder-type={m.role === "assistant" && showSidebarPlaceholder ? "sidebar_widget" : undefined}
                        className={
                          m.role === "user"
                            ? "chat-bubble-user text-sm leading-relaxed"
                            : "chat-bubble-ai text-sm leading-relaxed whitespace-pre-wrap" +
                              (showSidebarPlaceholder
                                ? " cursor-pointer hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-primary-accent/20 focus:ring-offset-1"
                                : "")
                        }
                      >
                        {m.role === "assistant" ? (
                          <span className="min-w-0 block text-sm leading-relaxed">
                            <MessageWithVenueRatings
                              content={m.content}
                              placeholder={m.stream ? "…" : ""}
                            />
                            {m.stream && (
                              <span className="inline-flex items-center gap-1 ml-1 align-middle" aria-hidden>
                                <span className="h-1.5 w-1.5 rounded-full bg-stone-400 animate-bounce [animation-delay:0ms]" />
                                <span className="h-1.5 w-1.5 rounded-full bg-stone-400 animate-bounce [animation-delay:150ms]" />
                                <span className="h-1.5 w-1.5 rounded-full bg-stone-400 animate-bounce [animation-delay:300ms]" />
                              </span>
                            )}
                          </span>
                        ) : (
                          <span className="block text-sm leading-relaxed">{m.content || ""}</span>
                        )}
                      </div>
                      {m.role === "assistant" && showSidebarPlaceholder && (
                        <VenueListPlaceholder
                          count={sidebarItems.length || (restaurantList?.messageIndex === i ? (restaurantList?.items?.length ?? 0) : 0)}
                          isSidebarOpen={restaurantList?.messageIndex === i && restaurantList?.placeholderType === "venue_list"}
                          onOpenSidebar={() => setRestaurantList((prev) => {
                            const items = sidebarItems.length > 0 ? sidebarItems : (prev?.messageIndex === i && (prev?.items?.length ?? 0) > 0 ? prev.items : []);
                            return { messageIndex: i, items, placeholderType: "venue_list" };
                          })}
                        />
                      )}
                    </div>
                  </div>
                  );
                })}
              </div>
            )}
          </div>
          {showScrollToBottom && messages.length > 0 && (
            <Button
              variant="secondary"
              size="icon"
              onClick={() => scrollToBottom("smooth")}
              className="absolute bottom-6 left-1/2 -translate-x-1/2 shadow-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-900"
              aria-label="Scroll to bottom"
            >
              <ArrowDownToLine className="h-4 w-4" />
            </Button>
          )}
        </div>

        <div className="shrink-0 p-6 bg-white border-t border-slate-50">
          <div className="max-w-3xl mx-auto relative">
            <Textarea
              placeholder="Ask for a table, neighborhood, or time..."
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && (e.preventDefault(), sendMessage())}
              rows={1}
              className="min-h-0 w-full resize-none rounded-full bg-slate-50 border border-slate-100 py-4 pl-6 pr-[4.5rem] text-[14px] placeholder:text-slate-400 focus-visible:outline-none focus-visible:border-[var(--color-primary-accent)]/30 focus-visible:ring-4 focus-visible:ring-[var(--color-primary-accent)]/5 border-0"
              disabled={loading}
            />
            <Button
              size="icon"
              onClick={sendMessage}
              disabled={loading}
              className="absolute right-2 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full bg-[var(--color-primary-accent)] text-white hover:brightness-110 shadow-lg shrink-0"
              aria-label="Send message"
            >
              <Send className="h-5 w-5" />
            </Button>
          </div>
        </div>
        </section>
        </motion.main>
        <AnimatePresence>
          {restaurantList?.placeholderType === "venue_list" && (
            <motion.div
              key="restaurant-sidebar"
              initial={{ width: 0, opacity: 0 }}
              animate={{ width: 320, opacity: 1 }}
              exit={{ width: 0, opacity: 0 }}
              transition={{ type: "tween", duration: 0.35, ease: [0.32, 0.72, 0, 1] }}
              className="z-10 flex h-full shrink-0 flex-col overflow-visible"
            >
              <RestaurantListSidebar
                items={restaurantList?.items ?? []}
                onBook={(venueName) => setInput(`Book ${venueName}`)}
                onClose={() => setRestaurantList(null)}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      </div>
    </div>
  );
}

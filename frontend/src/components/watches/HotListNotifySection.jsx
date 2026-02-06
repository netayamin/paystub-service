import { formatTimeAgoShort } from "@/lib/formatTimes";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

const NEW_MATCH_WINDOW_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Build a flat list of venue cards from notifications.
 */
function flattenVenueCards(notifications) {
  const cards = [];
  const now = Date.now();
  for (const n of notifications || []) {
    const createdMs = n.created_at ? new Date(n.created_at).getTime() : 0;
    const isNew = now - createdMs < NEW_MATCH_WINDOW_MS;
    const venues = n.new_venues?.length
      ? n.new_venues
      : (n.new_names || []).map((name) => ({ name, resy_url: null }));
    for (const v of venues) {
      cards.push({
        venueName: v.name,
        resyUrl: v.resy_url ?? null,
        created_at: n.created_at,
        criteria_summary: n.criteria_summary,
        notificationId: n.id,
        isNew,
      });
    }
  }
  cards.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
  return cards;
}

/**
 * Alerts: found matches. Supports theme="dark" for sidebar (dark bg, light text, blue BOOK).
 */
export function HotListNotifySection({
  notifications = [],
  expandedId,
  onExpandToggle,
  availabilityByNotificationId,
  loadingAvailabilityId,
  onLoadAvailability,
  onMarkRead,
  theme = "light",
  className,
}) {
  const cards = flattenVenueCards(notifications);
  const isDark = theme === "dark";

  if (!cards.length) {
    return (
      <div className={cn("px-3 py-4 text-center", className)}>
        <p className={cn("text-sm font-medium", isDark ? "text-slate-400" : "text-slate-600")}>No matches yet.</p>
        <p className={cn("mt-2 text-xs", isDark ? "text-slate-500" : "text-slate-500")}>
          <strong className={isDark ? "text-slate-300 font-semibold" : "text-slate-700 font-semibold"}>Specific restaurants:</strong> In Active Monitors, add a job that watches a list of places—you&apos;ll see a match here when any get availability.
        </p>
        <p className={cn("mt-1 text-xs", isDark ? "text-slate-500" : "text-slate-500")}>
          <strong className={isDark ? "text-slate-300 font-semibold" : "text-slate-700 font-semibold"}>New restaurants:</strong> Add a &quot;check every N min&quot; job (no list)—you&apos;ll see matches when new places appear for your date and time.
        </p>
      </div>
    );
  }

  return (
    <section className={cn("", className)}>
      <ul className={cn("", isDark && "divide-y divide-slate-600/50")}>
        {cards.map((card, index) => (
          <li
            key={`${card.notificationId}-${card.venueName}-${index}`}
            className={cn(
              isDark
                ? "p-3 border-b border-slate-600/50 hover:bg-slate-700/30 last:border-b-0" + (card.isNew ? " border-l-2 border-l-emerald-500" : "")
                : "list-row " + (card.isNew ? "bg-orange-50/30" : "")
            )}
          >
            <div className="flex-1 min-w-0">
              <div className="flex justify-between mb-1">
                <span className={cn(
                  "text-[9px] font-bold uppercase tracking-tighter",
                  isDark ? (card.isNew ? "text-emerald-400" : "text-slate-400") : (card.isNew ? "text-[var(--color-primary-accent)]" : "text-slate-400")
                )}>
                  {card.isNew ? "Instant Match" : "Available"}
                </span>
                <span className={cn("text-[9px] uppercase tabular-nums", isDark ? "text-slate-500" : "text-slate-400")}>{formatTimeAgoShort(card.created_at)}</span>
              </div>
              <p className={cn("text-[13px] font-bold truncate", isDark ? "text-slate-100" : "text-slate-900")} title={card.venueName}>{card.venueName}</p>
              <p className={cn("text-[11px]", isDark ? "text-slate-500" : "text-slate-500")}>{card.criteria_summary || "—"}</p>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              {card.resyUrl ? (
                <a href={card.resyUrl} target="_blank" rel="noopener noreferrer" className="action-btn-primary">
                  Book
                </a>
              ) : (
                <button type="button" disabled className={cn("h-8 px-5 flex items-center justify-center text-[10px] font-bold uppercase rounded-full", isDark ? "bg-slate-600 text-slate-500" : "bg-slate-200 text-slate-500")}>
                  Book
                </button>
              )}
              {onMarkRead && (
                <button
                  type="button"
                  onClick={() => onMarkRead(card.notificationId)}
                  className={cn(
                    "h-8 w-8 flex items-center justify-center rounded-full transition-colors",
                    isDark ? "text-slate-400 hover:text-slate-200 hover:bg-slate-600/50" : "text-slate-400 hover:text-slate-600 hover:bg-slate-100"
                  )}
                  aria-label="Clear"
                  title="Clear"
                >
                  <X className="h-3.5 w-3.5" strokeWidth={2} />
                </button>
              )}
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}

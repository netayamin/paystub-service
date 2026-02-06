import { Activity } from "lucide-react";
import { NotificationDot } from "@/components/ui/notification-dot";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";

/** Format YYYY-MM-DD to "FEB 14" for column headers */
function formatDateHeader(dateStr) {
  if (!dateStr) return "—";
  try {
    const d = new Date(dateStr + "T12:00:00");
    const months = "JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC";
    const month = months.split(" ")[d.getMonth()];
    return `${month} ${d.getDate()}`;
  } catch {
    return dateStr;
  }
}

/** Format time_filter "20:00" -> "8:00PM", "19:30" -> "7:30PM" */
function formatTimeFilter(timeFilter) {
  if (!timeFilter) return null;
  const match = String(timeFilter).trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return timeFilter;
  const h = parseInt(match[1], 10);
  const m = match[2];
  const hour = h % 12 || 12;
  const ampm = h < 12 ? "AM" : "PM";
  return `${hour}:${m}${ampm}`;
}

/**
 * Active monitors. Two variants:
 * - inline: horizontal card with date columns (for main area).
 * - sidebar: vertical list by date for dark left sidebar (FOUND TABLES below, ACTIVE MONITORS style).
 */
export function JobsRunningSection({
  intervalWatches = [],
  notifyRequests = [],
  onCancelWatch,
  onCancelRequest,
  variant = "inline",
  className,
}) {
  const entries = [];

  intervalWatches.forEach((w) => {
    const isSpecific = Array.isArray(w.venue_names) && w.venue_names.length > 0;
    const names = (w.venue_names || []).filter(Boolean);
    const title = isSpecific && names.length > 0 ? names[0] + (names.length > 1 ? ` +${names.length - 1}` : "") : "Scout";
    const timeStr = formatTimeFilter(w.time_filter) || w.date_str || "—";
    const partyStr = String(w.party_size || 2) + "P";
    entries.push({
      id: `interval-${w.id}`,
      type: "interval",
      dateKey: w.date_str || "",
      dateLabel: formatDateHeader(w.date_str),
      title,
      timeStr,
      partyStr,
      pulseDot: "active",
      onCancel: () => onCancelWatch?.(w.id),
    });
  });

  notifyRequests.forEach((r) => {
    const title = r.title || r.venue_name || "Notify";
    const timeStr = r.time_filter ? formatTimeFilter(r.time_filter) : null;
    entries.push({
      id: `notify-${r.id}`,
      type: "notify",
      dateKey: r.date_str || "",
      dateLabel: formatDateHeader(r.date_str),
      title,
      timeStr: timeStr || r.date_str || "—",
      partyStr: String(r.party_size || 2) + "P",
      pulseDot: r.status === "notified" ? "active" : "warning",
      onCancel: () => onCancelRequest?.(r.id),
    });
  });

  const total = entries.length;
  const byDate = entries.reduce((acc, e) => {
    const key = e.dateKey || "";
    if (!acc[key]) acc[key] = [];
    acc[key].push(e);
    return acc;
  }, {});
  const dateKeys = total === 0 ? [] : Object.keys(byDate).sort();

  if (variant === "sidebar") {
    return (
      <div className={cn("flex flex-col min-h-0 overflow-hidden", className)}>
        <div className="shrink-0 p-4 border-b border-slate-50 flex justify-between items-center bg-white sticky top-0 z-10">
          <h2 className="ui-heading flex items-center gap-2">
            <Activity className="w-4 h-4 text-[var(--color-primary-accent)]" strokeWidth={1.5} />
            Active Monitors
          </h2>
          <span className="text-[10px] font-bold text-slate-400">{total} Active</span>
        </div>
        <ScrollArea className="flex-1 min-h-0">
          {total === 0 ? (
            <p className="px-3 py-4 text-xs text-slate-500">No monitors yet. Ask the agent to watch or notify.</p>
          ) : (
            dateKeys.map((dateKey) => {
              const list = byDate[dateKey] || [];
              const huntCount = list.length;
              return (
                <div key={dateKey} className="border-b border-slate-100 last:border-b-0">
                  <div className="px-4 py-2 bg-slate-50 border-b border-slate-100 flex items-center justify-between">
                    <span className="text-[10px] font-bold uppercase tracking-tighter text-slate-600">
                      {dateKey ? formatDateHeader(dateKey) : "—"}
                    </span>
                    <span className="text-[10px] font-bold text-slate-400">{huntCount} Hunt{huntCount !== 1 ? "s" : ""}</span>
                  </div>
                  {list.map((e) => (
                    <div
                      key={e.id}
                      className="px-4 py-3 border-b border-slate-50 last:border-b-0 hover:bg-slate-50/80 group flex items-center gap-3"
                    >
                      {e.pulseDot === "active" ? <NotificationDot className="shrink-0" /> : <span className={cn("pulse-dot shrink-0", e.pulseDot)} aria-hidden />}
                      <div className="min-w-0 flex-1">
                        <p className="text-[13px] font-semibold text-slate-800 truncate" title={e.title}>{e.title}</p>
                        <p className="text-[11px] text-slate-500 mt-0.5">{e.partyStr} • {e.timeStr}</p>
                      </div>
                      {e.onCancel && (
                        <button
                          type="button"
                          onClick={(ev) => { ev.stopPropagation(); e.onCancel(); }}
                          className="text-[10px] font-bold uppercase text-slate-400 hover:text-slate-600 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                        >
                          Cancel
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              );
            })
          )}
        </ScrollArea>
      </div>
    );
  }

  return (
    <div
      className={cn(
        "flex min-h-[160px] max-h-[220px] w-full rounded-xl border border-slate-200 bg-white shadow-[var(--shadow-layered)] overflow-hidden",
        className
      )}
    >
      {/* Left: MISSIONS summary */}
      <div className="w-28 shrink-0 border-r border-slate-100 flex flex-col justify-center px-5 py-4 bg-slate-50/50">
        <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Missions</span>
        <div className="flex items-baseline gap-1 mt-0.5">
          <span className="text-3xl font-bold text-slate-900 tracking-tighter tabular-nums">{total}</span>
        </div>
        <div className="mt-3 pt-3 border-t border-slate-200/50 flex items-center gap-2">
          <span className="pulse-dot active" aria-hidden />
          <span className="text-xs font-semibold text-emerald-600 uppercase">Live</span>
        </div>
      </div>

      {/* Center: date columns fill 100% width; size to content (wider when needed), grow to use extra space */}
      <div className="flex-1 flex min-w-0 overflow-x-auto no-scrollbar bg-[var(--color-linen)]">
        {total === 0 ? (
          <div className="flex-1 flex items-center justify-center px-6 py-8 text-center w-full">
            <p className="text-sm text-slate-600">No jobs yet. Ask the agent to watch restaurants or set a notify.</p>
          </div>
        ) : (
          <div className="flex h-full w-full min-w-full">
            {dateKeys.map((dateKey) => (
              <div
                key={dateKey}
                className="flex-auto min-w-[max(180px,max-content)] border-r border-slate-100 flex flex-col bg-white/50"
              >
                <div className="px-3 py-2 bg-slate-50/80 border-b border-slate-100 shrink-0">
                  <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">
                    {dateKey ? formatDateHeader(dateKey) : "—"}
                  </span>
                </div>
                <ScrollArea className="flex-1 min-h-0">
                  <div className="space-y-0">
                  {(byDate[dateKey] || []).map((e) => (
                    <div
                      key={e.id}
                      className="py-2 px-3 border-b border-slate-100 last:border-b-0 hover:bg-white/80 transition-colors group"
                    >
                      <div className="flex items-start justify-between gap-1">
                        <span className="text-sm font-semibold text-slate-900 truncate flex-1 min-w-0" title={e.title}>
                          {e.title}
                        </span>
                        {e.pulseDot === "active" ? <NotificationDot className="shrink-0 mt-1.5" /> : <span className={cn("pulse-dot shrink-0 mt-1.5", e.pulseDot)} aria-hidden />}
                      </div>
                      <div className="flex items-center justify-between gap-2 mt-0.5">
                        <span className="text-xs text-slate-500">{e.timeStr}</span>
                        <span className="text-xs font-semibold text-slate-500 tabular-nums">{e.partyStr}</span>
                      </div>
                      {e.onCancel && (
                        <button
                          type="button"
                          onClick={(ev) => { ev.stopPropagation(); e.onCancel(); }}
                          className="mt-1 text-xs font-semibold uppercase tracking-wider text-slate-400 hover:text-slate-600 opacity-0 group-hover:opacity-100 transition-opacity"
                        >
                          Cancel
                        </button>
                      )}
                    </div>
                  ))}
                  </div>
                </ScrollArea>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

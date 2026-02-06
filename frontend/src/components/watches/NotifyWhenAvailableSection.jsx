import { Button } from "@/components/ui/button";
import { formatLastChecked } from "@/lib/formatTimes";
import { cn } from "@/lib/utils";
import { TimeSlots } from "./TimeSlots";

/**
 * One-off venue alerts: one request per venue; we check until we find a table, then show times here.
 * Distinct from recurring monitors (which run on a schedule and alert in Found Matches).
 */
export function NotifyWhenAvailableSection({
  notifyRequests = [],
  onCancelRequest,
  onRefresh,
  className,
}) {
  return (
    <section className={cn("space-y-3", className)}>
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          One-off venue alerts
        </h3>
        {onRefresh && (
          <Button variant="ghost" size="sm" className="h-7 text-xs shrink-0" onClick={onRefresh}>
            Refresh
          </Button>
        )}
      </div>
      {notifyRequests.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          None. Add a single-venue request (e.g. &quot;notify me when Carbone has a table Friday for 2&quot;). We check until we find it and show times here—unlike recurring monitors, this is one request per venue, no schedule.
        </p>
      ) : (
        <ul className="space-y-2">
          {notifyRequests.map((r) => (
            <li
              key={r.id}
              className="rounded-lg border border-border bg-card p-3 text-sm shadow-sm"
            >
              <div className="font-medium text-foreground">
                {r.title || r.venue_name}
              </div>
              {r.title && (
                <div className="text-xs text-muted-foreground">{r.venue_name}</div>
              )}
              <div className="mt-1 text-xs text-muted-foreground">
                {r.date_str} · {r.party_size} people
              </div>
              <div className="mt-2">
                {r.status === "notified" ? (
                  <>
                    <span className="text-xs font-medium text-green-600 dark:text-green-500">
                      ✓ Available
                    </span>
                    {(r.found_times || []).length > 0 && (
                      <div className="mt-1.5">
                        <span className="text-xs text-muted-foreground">Times: </span>
                        <TimeSlots slots={r.found_times} maxVisible={6} />
                      </div>
                    )}
                  </>
                ) : (
                  <span className="text-xs text-muted-foreground">Watching…</span>
                )}
              </div>
              {r.last_checked_at && (
                <div className="mt-1 text-xs text-muted-foreground">
                  {formatLastChecked(r.last_checked_at)}
                </div>
              )}
              <Button
                variant="ghost"
                size="sm"
                className="mt-2 h-7 text-xs"
                onClick={() => onCancelRequest?.(r.id)}
              >
                Cancel
              </Button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

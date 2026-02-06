/**
 * Error reporter: lists recent auto-booking attempts (success and failed).
 * Failed attempts show error_message so the user can see what went wrong.
 */
const API_BASE = "";
const RESY_VENUE_BASE = "https://www.resy.com/cities/new-york-ny/venues";

function slug(name) {
  if (!name || typeof name !== "string") return "";
  return name
    .toLowerCase()
    .replace(/'/g, "")
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9-]/g, "");
}

export function BookingErrorsSection({ attempts = [], onRefresh }) {
  const failed = attempts.filter((a) => a.status === "failed");
  const succeeded = attempts.filter((a) => a.status === "success");

  return (
    <div className="space-y-4">
      <p className="text-xs text-muted-foreground">
        Auto-booking runs when a venue becomes available. Success and errors are listed below.
      </p>
      {attempts.length === 0 ? (
        <p className="text-xs text-muted-foreground">No booking attempts yet.</p>
      ) : (
        <ul className="space-y-2">
          {attempts.map((a) => {
            const isFailed = a.status === "failed";
            const venueSlug = slug(a.venue_name);
            const resyUrl = venueSlug
              ? `${RESY_VENUE_BASE}/${venueSlug}?date=${a.date_str}&seats=${a.party_size}`
              : null;
            return (
              <li
                key={a.id}
                className={`rounded-md border px-2 py-2 text-xs ${
                  isFailed ? "border-destructive/30 bg-destructive/5" : "border-input bg-muted/30"
                }`}
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium truncate">{a.venue_name}</span>
                  <span
                    className={`shrink-0 rounded px-1.5 py-0.5 text-[10px] font-medium ${
                      isFailed ? "bg-destructive/20 text-destructive" : "bg-green-500/20 text-green-700 dark:text-green-400"
                    }`}
                  >
                    {a.status === "success" ? "Booked" : "Failed"}
                  </span>
                </div>
                <div className="mt-1 text-muted-foreground">
                  {a.date_str} · {a.party_size} seats
                </div>
                {isFailed && a.error_message && (
                  <p className="mt-1.5 text-destructive/90 break-words">{a.error_message}</p>
                )}
                {resyUrl && (
                  <a
                    href={resyUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-1.5 inline-block text-primary text-[11px] underline"
                  >
                    Open on Resy →
                  </a>
                )}
                {a.created_at && (
                  <p className="mt-1 text-[10px] text-muted-foreground">
                    {new Date(a.created_at).toLocaleString()}
                  </p>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {onRefresh && (
        <button
          type="button"
          onClick={onRefresh}
          className="text-xs text-primary underline hover:no-underline"
        >
          Refresh
        </button>
      )}
    </div>
  );
}

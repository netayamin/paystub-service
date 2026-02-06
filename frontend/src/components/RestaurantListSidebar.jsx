import { Calendar, Star, UtensilsCrossed, X } from "lucide-react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";

/**
 * Sidebar that displays a parsed list of restaurants (Available Inventory).
 * Concierge-style: Romantic Spots header, list-row items with rating/neighborhood, Live Inventory footer.
 */
export function RestaurantListSidebar({
  items = [],
  onBook,
  onClose,
  filterPills,
  resultsDate,
  className,
}) {
  const count = items.length;
  const dateLabel = resultsDate ? new Date(resultsDate).toLocaleDateString("en-US", { month: "short", day: "numeric" }) : null;

  return (
    <aside
      className={cn(
        "section-card flex h-full min-h-0 w-[320px] shrink-0 flex-col overflow-hidden z-10",
        className
      )}
    >
      <div className="z-10 flex shrink-0 flex-col gap-2 px-4 py-3 border-b border-slate-100">
        <div className="flex items-center justify-between gap-2">
          <h2 className="ui-heading text-xs font-extrabold uppercase tracking-tighter">Romantic Spots</h2>
          {onClose && (
            <button
              type="button"
              onClick={onClose}
              className="p-1.5 rounded-md text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
        {count > 0 && (
          <div className="flex items-center gap-2">
            <span className="pulse-dot active h-2 w-2" aria-hidden />
            <span className="text-[11px] font-semibold text-slate-600">
              {dateLabel ? `${dateLabel} • ` : ""}{count} Result{count !== 1 ? "s" : ""}
            </span>
          </div>
        )}
        {Array.isArray(filterPills) && filterPills.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {filterPills.map((label, idx) => (
              <span key={idx} className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600">
                {label}
              </span>
            ))}
          </div>
        )}
      </div>

      <ScrollArea className="min-h-0 min-w-0 flex-1">
        {items.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-3 px-4 py-10 text-center">
            <p className="text-sm font-medium text-slate-500">No list for this message.</p>
            <p className="text-xs text-slate-400">Ask for restaurants with a date and time to see results here.</p>
          </div>
        ) : (
          <ul className="">
            {items.map((item, i) => {
              const imageUrl = item.image_url || item.imageUrl;
              const neighborhood = item.neighborhood || item.area || "Resy";
              const rating = item.rating ?? item.rating_score;
              return (
                <li key={`${item.name}-${i}`} className="list-row">
                  {imageUrl ? (
                    <div className="h-10 w-10 shrink-0 overflow-hidden rounded-md bg-slate-100">
                      <img src={imageUrl} alt="" className="h-full w-full object-cover" />
                    </div>
                  ) : (
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-slate-100 text-slate-400">
                      <UtensilsCrossed className="h-5 w-5" />
                    </div>
                  )}
                  <div className="min-w-0 flex-1 overflow-hidden">
                    <h4 className="truncate text-[13px] font-bold text-slate-800" title={item.name}>{item.name}</h4>
                    <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
                      {rating != null && (
                        <span className="flex items-center gap-0.5 text-[12px] font-semibold text-slate-700">
                          <Star className="h-3.5 w-3.5 fill-[var(--color-rating-gold)] text-[var(--color-rating-gold)]" strokeWidth={1.5} />
                          {Number(rating).toFixed(1)}
                        </span>
                      )}
                      <span className="text-[11px] text-slate-500 truncate" title={neighborhood}>{neighborhood}</span>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => onBook?.(item.name)}
                    className="icon-btn-accent shrink-0"
                    aria-label={`Book ${item.name}`}
                  >
                    <Calendar className="h-4 w-4" strokeWidth={1.5} />
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </ScrollArea>

      {items.length > 0 && (
        <div className="shrink-0 flex items-center justify-center gap-2 border-t border-slate-100 bg-slate-50/50 px-4 py-2.5">
          <span className="pulse-dot active h-1.5 w-1.5" aria-hidden />
          <span className="text-[9px] font-bold uppercase tracking-tighter text-[var(--color-primary-accent)]">Live Inventory Tracking</span>
        </div>
      )}
    </aside>
  );
}

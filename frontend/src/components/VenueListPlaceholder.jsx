import { cn } from "@/lib/utils";

/**
 * In-chat link to open the Available Inventory sidebar.
 * Concierge-style: blue underlined "N real-time matches found".
 */
export function VenueListPlaceholder({ count, isSidebarOpen, onOpenSidebar, className }) {
  const label =
    count >= 1
      ? `${count} real-time match${count === 1 ? "" : "es"} found`
      : "Open Available Inventory";

  return (
    <button
      type="button"
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        onOpenSidebar?.();
      }}
      className={cn(
        "cursor-pointer text-sm font-medium text-brand-blue underline underline-offset-2 hover:text-brand-blue/80 focus:outline-none focus:ring-2 focus:ring-brand-blue/30 focus:ring-offset-1 rounded",
        isSidebarOpen && "text-brand-blue/80 no-underline",
        className
      )}
      data-placeholder-type="sidebar_widget"
    >
      {label}
    </button>
  );
}

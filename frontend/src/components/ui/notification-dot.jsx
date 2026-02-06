import { cn } from "@/lib/utils";

/**
 * Blue notification dot with glow/pulse. Use for "active" or "live" indicators
 * (e.g. Found Tables header, Active Monitors rows).
 */
export function NotificationDot({ className, ...props }) {
  return (
    <span
      className={cn("notification-dot h-2 w-2 shrink-0 rounded-full", className)}
      aria-hidden
      {...props}
    />
  );
}

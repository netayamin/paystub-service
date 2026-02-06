import { formatTimeSlot } from "@/lib/formatTimes";
import { cn } from "@/lib/utils";

/**
 * Renders a list of time slots (e.g. "17:30", "19:00") as readable chips for better scanability.
 */
export function TimeSlots({ slots = [], maxVisible = 8, className }) {
  if (!Array.isArray(slots) || slots.length === 0) return null;
  const visible = slots.slice(0, maxVisible);
  const remaining = slots.length - maxVisible;

  return (
    <div className={cn("flex flex-wrap gap-1.5", className)}>
      {visible.map((slot, i) => (
        <span
          key={i}
          className="inline-flex items-center rounded-full bg-brand-blue/10 px-2.5 py-0.5 text-[10px] font-medium text-brand-blue tabular-nums"
        >
          {formatTimeSlot(slot)}
        </span>
      ))}
      {remaining > 0 && (
        <span className="text-xs text-stone-500 py-0.5">+{remaining}</span>
      )}
    </div>
  );
}

/**
 * Inline text list of times (e.g. "5:30 PM, 7:00 PM, 9:15 PM").
 */
export function TimeSlotsInline({ slots = [], maxCount = 6 }) {
  if (!Array.isArray(slots) || slots.length === 0) return null;
  const shown = slots.slice(0, maxCount);
  const more = slots.length - maxCount;
  const text = shown.map(formatTimeSlot).join(", ") + (more > 0 ? ` +${more} more` : "");
  return <span className="tabular-nums">{text}</span>;
}

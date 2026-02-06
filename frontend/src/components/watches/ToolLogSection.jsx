import { useState } from "react";
import { cn } from "@/lib/utils";
import { FileText, ChevronDown, ChevronRight } from "lucide-react";

/**
 * History: tool call entries. Dashboard-style — white card, rows with icon, status pills, expandable details.
 */
export function ToolLogSection({ entries = [], onRefresh, className }) {
  const [expandedId, setExpandedId] = useState(null);

  if (entries.length === 0) {
    return (
      <div className={cn("px-4 py-6 text-center", className)}>
        <p className="text-sm text-slate-600">No tool calls yet. Use the chat to run searches, set up watches, or book—each tool call will appear here.</p>
        {onRefresh && (
          <button type="button" onClick={onRefresh} className="mt-2 text-xs font-medium text-brand-blue hover:underline">
            Refresh
          </button>
        )}
      </div>
    );
  }

  return (
    <div className={cn("", className)}>
      {onRefresh && (
        <div className="px-3 py-2 border-b border-slate-50 flex justify-end">
          <button type="button" onClick={onRefresh} className="text-xs font-medium text-brand-blue hover:underline">
            Refresh
          </button>
        </div>
      )}
      <ul className="divide-y divide-slate-50">
        {entries.map((entry) => {
          const id = entry.id ?? entry.created_at;
          const isExpanded = expandedId === id;
          const isBooking = entry.type === "booking_attempt";
          const args = entry.arguments || {};
          const hasArgs = Object.keys(args).length > 0;
          const success = isBooking && entry.result_status === "success";
          const failed = isBooking && entry.result_status === "failed";

          return (
            <li
              key={`${entry.type}-${id}-${entry.created_at}`}
              className={cn(
                "text-sm",
                failed && "bg-red-50/30"
              )}
            >
              <button
                type="button"
                className="w-full flex items-center gap-3 p-3 text-left hover:bg-slate-50 transition-colors border-b border-slate-50"
                onClick={() => setExpandedId(isExpanded ? null : id)}
              >
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-slate-200 bg-slate-50 text-slate-500">
                  <FileText className="h-3.5 w-3.5" strokeWidth={1.5} />
                </div>
                <div className="min-w-0 flex-1">
                  <span className="text-sm font-semibold text-slate-800 truncate block">{entry.tool_name}</span>
                  <span className="text-xs text-slate-400">
                    {entry.created_at ? new Date(entry.created_at).toLocaleString() : ""}
                  </span>
                </div>
                {isBooking && (
                  <span
                    className={cn(
                      "shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold uppercase",
                      success && "bg-emerald-50 text-emerald-600 border border-emerald-100",
                      failed && "bg-red-50 text-red-600 border border-red-100"
                    )}
                  >
                    {success ? "Success" : "Failed"}
                  </span>
                )}
                {isExpanded ? (
                  <ChevronDown className="h-4 w-4 shrink-0 text-slate-400" />
                ) : (
                  <ChevronRight className="h-4 w-4 shrink-0 text-slate-400" />
                )}
              </button>
              {(hasArgs || isBooking) && isExpanded && (
                <div className="border-t border-slate-100 bg-slate-50/50 px-3 pb-3 pt-2">
                  {hasArgs && (
                    <pre className="text-xs overflow-x-auto whitespace-pre-wrap break-words font-mono text-slate-500">
                      {JSON.stringify(args, null, 2)}
                    </pre>
                  )}
                  {isBooking && entry.result_summary && (
                    <p className="mt-1 text-xs text-slate-600">{entry.result_summary}</p>
                  )}
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}

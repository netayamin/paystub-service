import { useState } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Bell, Clock, Trash2 } from "lucide-react";
import { NotificationDot } from "@/components/ui/notification-dot";
import { HotListNotifySection } from "./HotListNotifySection";
import { ToolLogSection } from "./ToolLogSection";

export function WatchesTabs({
  watches,
  countdownNow,
  expandedNotificationId,
  setExpandedNotificationId,
  availabilityByNotificationId,
  loadingAvailabilityId,
  fetchAvailabilityForNotification,
  fetchWatches,
  cancelIntervalWatch,
  cancelNotifyRequest,
  markNotificationRead,
  onClearAllNotifications,
  notificationPermission,
  logEntries = [],
  fetchLogs,
  theme = "light",
}) {
  const [activeTab, setActiveTab] = useState("hotlist");
  const notifications = watches?.notifications || [];
  const hasNotifications = notifications.length > 0;
  const isDark = theme === "dark";

  return (
    <div className="flex h-full flex-col min-h-0">
      <div className={cn(
        "shrink-0 p-4 border-b flex justify-between items-center bg-white sticky top-0 z-10",
        isDark ? "border-slate-600/50 bg-slate-800/60" : "border-slate-50"
      )}>
        <h2 className={cn("ui-heading flex items-center gap-2", isDark && "text-slate-200")}>
          <Bell className={cn("w-4 h-4", isDark ? "text-slate-400" : "text-[var(--color-primary-accent)]")} strokeWidth={1.5} />
          Found Tables
        </h2>
        <div className="flex items-center gap-1">
          {activeTab === "hotlist" && hasNotifications && onClearAllNotifications && (
            <Button
              type="button"
              variant="ghost"
              size="icon"
              onClick={onClearAllNotifications}
              className={cn(
                "h-7 w-7 shrink-0",
                isDark ? "text-slate-400 hover:text-slate-200 hover:bg-slate-600/50" : "text-slate-500 hover:text-slate-700 hover:bg-slate-100"
              )}
              aria-label="Clear all"
              title="Clear all"
            >
              <Trash2 className="h-3.5 w-3.5" strokeWidth={1.5} />
            </Button>
          )}
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => setActiveTab(activeTab === "log" ? "hotlist" : "log")}
            className={cn(
              "h-7 w-7 shrink-0",
              isDark ? "text-slate-400 hover:text-slate-200 hover:bg-slate-600/50" : "text-slate-500 hover:text-slate-700 hover:bg-slate-100",
              activeTab === "log" && (isDark ? "bg-slate-600/50 text-slate-200" : "bg-slate-100 text-slate-700")
            )}
            aria-label={activeTab === "log" ? "Show alerts" : "Show history"}
            title={activeTab === "log" ? "Show alerts" : "Show history"}
          >
            <Clock className="h-4 w-4" strokeWidth={1.5} />
          </Button>
        </div>
      </div>
      {notificationPermission === "denied" && (
        <p className={cn(
          "shrink-0 px-3 py-2 text-xs border-b",
          isDark ? "text-amber-400/90 bg-amber-900/20 border-slate-600/50" : "text-amber-700 bg-amber-50/80 border-slate-100"
        )}>
          Enable browser notifications to get alerts when something becomes available.
        </p>
      )}
      <ScrollArea className="flex-1 min-h-0">
        {activeTab === "hotlist" && (
          <HotListNotifySection
            notifications={watches.notifications || []}
            expandedId={expandedNotificationId}
            onExpandToggle={setExpandedNotificationId}
            availabilityByNotificationId={availabilityByNotificationId}
            loadingAvailabilityId={loadingAvailabilityId}
            onLoadAvailability={fetchAvailabilityForNotification}
            onMarkRead={markNotificationRead}
            theme={theme}
          />
        )}
        {activeTab === "log" && (
          <ToolLogSection entries={logEntries} onRefresh={fetchLogs} />
        )}
      </ScrollArea>
    </div>
  );
}

# Notifications logic — how it works

Explanation of how "new drop" notifications work in the web app: data sources, UI surfaces, and where things can get confusing.

---

## 1. Two backend sources for "new" drops

The frontend uses **two different API calls** that both represent "tables that just opened":

| API | When it's called | What it's used for |
|-----|------------------|--------------------|
| **GET /chat/watches/just-opened** (no `dates` param) | Inside `fetchJustOpened`, after the main just-opened (with date filter). | Response is turned into `notificationDropsAllDates` via `buildDiscoveryDrops(..., "Anytime")`. This feeds the **red banner** and the "new drops" logic that updates `seenDropIds` and `newDropsByDate`. |
| **GET /chat/watches/new-drops?within_minutes=15** | Same `fetchJustOpened` run, right after the all-dates just-opened. | Response is the **only** source for **top-right toasts** and for **notification center** (bell panel). When we show a toast we also push that drop into `notifications` (and persist to localStorage). |

So:

- **Banner** and "new drop" counts by date come from **just-opened (all dates)**.
- **Toasts** and **bell notification list** come from **new-drops (15 min)**.

Backend:

- **just-opened** uses `opened_within_minutes = JUST_OPENED_WITHIN_MINUTES` (e.g. 5 min) when called with no dates for the notification fetch (the code path that sets `notificationDropsAllDates` doesn’t pass a time window; the backend uses its default).
- **new-drops** uses `within_minutes=15`.

So the time windows for "recent" can differ, and the two lists can be slightly different.

---

## 2. Three UI surfaces

### A. Top-right toasts

- **Data:** Only from **new-drops** response.
- **Logic:** For each drop in the response, if its `id` is not in `newDropsSeenIdsRef` and not already in the toast list, we push a toast and add the same item to `notifications`. Toast is removed after 7s.
- **First load:** We only toast for drops whose `detected_at` is in the last 90 seconds; older ones are marked as seen so we don’t toast for them.
- **Cap:** Max 8 toasts; `newDropsSeenIdsRef` is trimmed to 300 ids.

### B. Notification center (bell panel)

- **Data:** Same as toasts — each item is added when we show a toast from **new-drops**. So the list is "every drop we ever showed as a toast" (up to 80), persisted in localStorage under `dropfeed-notifications`.
- **Actions:** "Mark read," "Clear all," dismiss one. Read state and list are client-only (no backend).

### C. Red "New drops" banner

- **Data:** Comes from **just-opened (all dates)** via `notificationDropsAllDates`, with fallback to `newDropsAll` (from the main feed) when `notificationDropsAllDates` is empty. So the banner is driven by `dropsForNotifications = notificationDropsAllDates.length > 0 ? notificationDropsAllDates : newDropsAll`.
- **Logic:** A `useEffect` compares `dropsForNotifications` to `seenDropIds`. If there are ids in the list that aren’t in `seenDropIds`, we show the banner, set `newDropsList`, update `newDropsByDate`, and (on first load) only treat drops as "new" if they’re in the last 90 seconds.
- **Auto-dismiss:** Banner hides after 8 seconds (timer).

So:

- **Toasts + notification center** = one pipeline (new-drops only).
- **Banner** = different pipeline (just-opened all-dates, or feed), with its own "seen" set (`seenDropIds`).

---

## 3. IDs and "seen" state

- **Drop id:** Both APIs effectively use the same shape of id: `just-opened-${date_str}-${name_slug}` (from `buildDiscoveryDrops` for just-opened, and the same pattern in **new-drops** backend).
- **Two seen mechanisms:**
  - **newDropsSeenIdsRef:** Used so we don’t show the **same** drop as a toast twice. Filled from new-drops only.
  - **seenDropIds:** Used so we don’t keep showing the **banner** for the same drops. Filled from the `dropsForNotifications` list (just-opened all-dates or newDropsAll).

Because the banner and the toasts use different APIs and different seen sets, you can get:

- A drop that appears in the banner but never as a toast (if it’s in just-opened but not in new-drops 15 min window).
- A drop that appears as a toast (and in the bell) but not in the banner (if new-drops has it but just-opened all-dates doesn’t, or the banner logic has already marked it seen).

---

## 4. Flow summary

```
fetchJustOpened (every 15s + on visibility)
├── GET just-opened?dates=... (main feed)
├── GET just-opened (no dates) → notificationDropsAllDates → banner + seenDropIds
└── GET new-drops?within_minutes=15
    └── For each new id (not in newDropsSeenIdsRef):
        ├── Add toast (auto-remove 7s)
        └── Push to notifications (bell list, localStorage)
```

Banner visibility is then decided in a separate `useEffect` that watches `notificationDropsAllDates` / `newDropsAll` and `seenDropIds`.

---

## 5. What "fix" usually means

When people say "fix notifications," they often mean one or more of:

1. **Single source of truth:** Use one API (e.g. only **new-drops**) for both toasts and banner, so behavior and timing are consistent.
2. **Single "seen" notion:** One set of "already shown" ids for both toasts and banner, so we don’t double-show or miss showing in one place.
3. **Clear semantics:** e.g. "Toast = just appeared in last N min; Bell = history of those toasts; Banner = same as toast or scroll-to-new."
4. **Backend alignment:** Same time window (e.g. 15 min) and same id shape for both just-opened (all dates) and new-drops if we keep both, or remove one and use the other everywhere.

If you tell me which of these you want (e.g. "one API, one seen set, banner = same as toasts"), I can outline the exact code changes next.

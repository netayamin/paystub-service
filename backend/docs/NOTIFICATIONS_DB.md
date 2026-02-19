# Notifications: database design and scaling

## Why a DB for notifications?

- **Marked as seen stays:** Once a user marks a notification as read, it stays read (no re-showing on refresh or another device).
- **Scale:** Indexed by `recipient_id`, `read_at`, `created_at` so listing and unread counts stay fast.
- **Customization later:** `type` and JSONB `metadata` support new notification kinds and user preferences without schema churn.

## Schema (best-practice aligned)

References: [Facebook-like notification schema](https://www.w3tutorials.net/blog/database-schema-for-notification-system-similar-to-facebooks/), [scalable notification design](https://dev.to/ndohjapan/scalable-notification-system-design-for-50-million-users-database-design-4cl).

**Table: `user_notifications`**

| Column        | Type      | Purpose |
|---------------|-----------|---------|
| `id`          | SERIAL PK | Stable id for mark-read / dismiss. |
| `recipient_id`| VARCHAR(64) | Who receives. Today: client-generated id (e.g. `default-abc123`) from localStorage; later: `user_id` when you add auth. |
| `type`        | VARCHAR(32) | Kind of notification (`new_drop`, etc.). Enables filtering and future preference tables. |
| `read_at`     | TIMESTAMPTZ NULL | When the user marked it read. NULL = unread. |
| `created_at`  | TIMESTAMPTZ | When the notification was created. |
| `metadata`    | JSONB     | Type-specific payload (e.g. `name`, `date_str`, `resy_url`, `slots`) so new fields don’t require migrations. |

**Index:** `(recipient_id, read_at, created_at DESC)` for “my unread / recent” and unread counts.

## API (under `/chat`)

- **GET /chat/notifications** – List for `recipient_id` (from header `X-Recipient-Id` or query). `unread_only=true` for the notification center so read items don’t show.
- **POST /chat/notifications** – Create rows (e.g. when new drops arrive). Body: `{ "notifications": [ { "type": "new_drop", "metadata": { ... } } ] }`.
- **PATCH /chat/notifications/:id/read** – Mark one as read.
- **POST /chat/notifications/mark-all-read** – Mark all as read (“Clear all”).

## Frontend

- **Recipient id:** Stored in `localStorage` under `dropfeed-recipient-id` (generated once per browser). Sent as header `X-Recipient-Id` on all notification requests.
- **List:** Fetched from GET with `unread_only=true`; “Mark read” and “Clear all” call the API so read state is persisted.
- **New drops:** When the app receives new drops from the new-drops API, it POSTs them to `/chat/notifications` then refetches the list so new items appear with DB ids and persist.

## Later: preferences and scale

- **User preferences:** Add a table e.g. `user_notification_preferences (recipient_id, type, channel, enabled)` and filter or throttle by type/channel.
- **More types:** Add new `type` values and put type-specific data in `metadata`; no new columns needed.
- **Auth:** When you add users, use `user_id` as `recipient_id` (or migrate from device id to user id).
- **Volume:** If needed, partition by `recipient_id` or archive old read rows; index already targets per-recipient queries.

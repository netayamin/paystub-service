# Discovery: Poll → Normalize → Fingerprint → Compare → Emit

This doc maps our implementation to the standard algorithm for polling an external system and detecting new availability with low latency.

## Core problems

| Problem | What we do |
|--------|------------|
| **Stable identity** | Fingerprint = `slot_id` = hash(provider, venue_id, actual_time). One id per (restaurant + date + time); party size is in the query (bucket), not in the key. |
| **Cheap state** | Per bucket we store **prev_slot_ids** (last poll). Diff: `added = curr - prev`; baseline only bootstraps first prev. No full-JSON diff. |
| **Idempotent notifications** | `DropEvent.dedupe_key` = `bucket_id|slot_id|YYYY-MM-DDTHH:MM`. Insert is `ON CONFLICT (dedupe_key) DO NOTHING`. |
| **Scale across users** | We poll **per QueryKey** (bucket = date + time_slot), not per user. One job fills the feed; all users read the same API. |

## Algorithm we implement

1. **Normalize**  
   Resy response → list of entities. **Entity = slot** (venue + date + time). Party size is fixed per bucket (e.g. 2,4 from env).

2. **Fingerprint**  
   `slot_id = hash(provider, venue_id, actual_time)`. Deterministic, no raw JSON in the key.

3. **Compare**  
   - `curr_set` = set(slot_id for each row from this poll).  
   - **Added** = `curr_set - prev_set`. **Drops (for feed)** = only added slots whose venue had **zero slots** in the previous poll (venue went from no availability to some). We do not surface venues that already had other times and gained more times.

4. **TTL dedupe**  
   Before creating a `DropEvent`, check: already have one for (bucket_id, slot_id) with `opened_at` within last `NOTIFIED_DEDUPE_MINUTES`? If yes, skip new DropEvent. All added still go to `SlotAvailability`; only drops_venue_zero get a DropEvent (so "just opened" = venue had 0 before).

5. **Emit**  
   All **added** go to `SlotAvailability`. Only **drops_venue_zero minus recently_notified** get a new `DropEvent` (dedupe_key): i.e. only slots for venues that had **0 availability** in the previous poll. The **just-opened** API returns only slots that have a `DropEvent` in the time window (and are still open), so the feed shows only venues that went from fully booked to having availability — not venues that simply gained more time slots.

6. **Update state**  
   `prev_slot_ids = curr`. Baseline only for first prev or explicit refresh.

## TTL dedupe (notifiedSet)

- We **do not** compare to initial baseline forever; we only compare to **prev** (previous snapshot). So “added = curr − prev” and we can re-alert when a slot reappears after it was gone.
- To avoid spam when a slot flaps (disappears and reappears within minutes), we use a **notifiedSet with TTL**: we only create a `DropEvent` (and thus notify) if we have not already created one for (bucket_id, slot_id) in the last `NOTIFIED_DEDUPE_MINUTES` (env, default 30). Implemented by querying `DropEvent` for that bucket/slot with `opened_at >= now - TTL`; if any exist, we skip creating a new row. The slot still goes into `SlotAvailability` so the feed shows it.

## Scaling choices we already make

- **Poll per QueryKey**: Bucket = (date_str, time_slot). We poll each bucket on a schedule; no per-user polling.
- **Bounded diff**: We only store slot_id sets (and full payload only for emitted slots in `SlotAvailability`). Set size is O(slots per bucket), not O(response size).
- **Single owner per bucket**: Advisory lock per bucket so only one writer runs per bucket at a time; no double-emit from concurrent polls.
- **Fan-out**: API reads from `SlotAvailability` / feed; push/email consume `DropEvent` with dedupe_key.

## Optional improvements (not implemented)

- **Jitter**: Add a few seconds of random delay per bucket so many buckets don’t hit Resy at the same time (reduce thundering herd).
- **TTL seen set**: If product wants “notify again if slot reappears after 24h”, add a TTL to “seen” (or baseline) and treat expired entries as “new” again.
- **Dynamic poll interval**: Hot buckets (many drops) poll more often; cold buckets less often; backoff on 429/failures.

## Entity and key schema (current)

| Concept | Key | Stored where |
|--------|-----|---------------|
| QueryKey | `bucket_id` = `date_str_time_slot` (e.g. `2026-02-28_20:30`) | `DiscoveryBucket.bucket_id` |
| Entity | Slot = venue + date + time | — |
| Fingerprint | `slot_id` = hash(provider, venue_id, actual_time) | `DiscoveryBucket.baseline_slot_ids_json`, `prev_slot_ids_json`; `SlotAvailability.slot_id`; `DropEvent.slot_id` |
| Dedupe (emit) | `dedupe_key` = `bucket_id\|slot_id\|YYYY-MM-DDTHH:MM` | `DropEvent.dedupe_key` (unique) |

Party size is not in the fingerprint; it’s part of the **query** (we run one poll per bucket, and bucket uses `DISCOVERY_PARTY_SIZES`). So “same slot” is the same across party sizes; we could add party_size to the key if we wanted per-party-size dedupe.

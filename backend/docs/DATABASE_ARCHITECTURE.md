# Database architecture (graph view)

Snag / DropFeed **Postgres** layout: discovery and feed are **string-keyed** (`bucket_id`, `slot_id`, `venue_id`) more than formal `FOREIGN KEY` constraints. Edges below are **logical** relationships the code enforces.

---

## 1. Domain map (mental model)

| Domain | Tables | Role |
|--------|--------|------|
| **Discovery window** | `discovery_buckets` | One row per poll bucket `(market, date, time_slot)`; stores `prev` / baseline slot id JSON for diffs. |
| **Live projection** | `slot_availability` | Current Resy snapshot per `(bucket_id, slot_id)` — what the feed treats as open/closed. |
| **Drop facts** | `drop_events` | “Venue had zero slots → now has a slot” emits a row; tied to `(bucket_id, slot_id)`; pruned when slot closes or by retention. |
| **Session / metrics input** | `availability_state` | One row per open slot (upsert); closed rows aggregated then removed. Legacy: `availability_sessions`. |
| **Venues** | `venues` | Canonical venue profile + `last_drop_opened_at` (denormalized for follows without scanning `drop_events`). |
| **Aggregates** | `venue_metrics`, `market_metrics`, `venue_rolling_metrics` | Daily / rolling stats for ranking and enrichment (not user analytics dashboards). |
| **User / notify** | `notify_preferences`, `user_notifications`, `push_tokens` | Watch list, in-app activity, APNs device rows. |
| **Cache** | `feed_cache` | Precomputed JSON for fast `GET` feed paths. |
| **UX aux** | `recent_missed_drops` | “Just missed” style recent closes. |

---

## 2. ER diagram (tables & keys)

```mermaid
erDiagram
  discovery_buckets {
    string bucket_id PK
    string date_str
    string time_slot
    string market
    text baseline_slot_ids_json
    text prev_slot_ids_json
    int successful_poll_count
  }

  slot_availability {
    string bucket_id PK
    string slot_id PK
    string state
    string venue_id
    string slot_date
    string market
  }

  drop_events {
    int id PK
    string bucket_id
    string slot_id
    string dedupe_key UK
    timestamptz user_facing_opened_at
    string venue_id
    string eligibility_evidence
    timestamptz push_sent_at
    string market
  }

  availability_state {
    int id PK
    string bucket_id
    string slot_id
    timestamptz opened_at
    timestamptz closed_at
    string venue_id
    string market
  }

  venues {
    string venue_id PK
    string venue_name
    string market
    timestamptz last_drop_opened_at
  }

  venue_metrics {
    int id PK
    string venue_id
    date window_date
    int new_drop_count
  }

  venue_rolling_metrics {
    int id PK
    string venue_id
    date as_of_date
    float rarity_score
  }

  market_metrics {
    int id PK
    date window_date
    string metric_type
  }

  notify_preferences {
    int id PK
    string recipient_id
    string venue_name_normalized
    string preference
  }

  user_notifications {
    int id PK
    string recipient_id
    string type
    jsonb metadata
  }

  push_tokens {
    int id PK
    string device_token UK
  }

  feed_cache {
    string cache_key PK
    text payload_json
  }

  recent_missed_drops {
    int id PK
    string venue_name
    timestamptz gone_at
  }

  availability_sessions {
    int id PK
    string bucket_id
    string slot_id
  }

  discovery_buckets ||--o{ slot_availability : "bucket_id"
  discovery_buckets ||--o{ drop_events : "bucket_id"
  discovery_buckets ||--o{ availability_state : "bucket_id"

  slot_availability }o..o{ drop_events : "bucket_id plus slot_id live pair"

  venues ||--o{ drop_events : "venue_id optional"
  venues ||--o{ slot_availability : "venue_id optional"
  venues ||--o{ venue_metrics : "venue_id"
  venues ||--o{ venue_rolling_metrics : "venue_id"

  notify_preferences }o..o{ venues : "name match not FK"
```

---

## 3. Hot path: poll → projection → drop → feed

How a **bucket poll** touches tables (simplified):

```mermaid
flowchart TB
  subgraph poll [Bucket poll]
    B[discovery_buckets prev vs curr]
    B --> SA[slot_availability upsert open rows]
    B --> DE[drop_events insert if venue-zero add]
    B --> AS[availability_state upsert opens]
    B --> V[venues upsert + last_drop_opened_at]
    SA -->|slot leaves Resy set| DEL[delete SA row + drop_events for pair]
    DEL --> AGG[aggregate into venue_metrics / rolling]
  end

  subgraph read [API read]
    FC[feed_cache snapshot optional]
    DE2[drop_events + slot_availability]
    SA2[slot_availability still open]
    DE2 --> FEED[just-opened / feed ranking]
    SA2 --> FEED
    FC --> FEED
  end

  subgraph user [User]
    NP[notify_preferences]
    UN[user_notifications]
    PT[push_tokens]
    DE3[drop_events unsent]
    DE3 --> PUSH[push job]
    NP --> PUSH
    PT --> PUSH
  end
```

---

## 4. Cardinality cheatsheet

- **`discovery_buckets`**: ~28 active rows per market (14 days × 2 time slots); grows then prunes with window.
- **`slot_availability`**: on the order of **open Resy slots** across buckets (large but bounded by window + caps).
- **`drop_events`**: intended **≤ one row per open `(bucket_id, slot_id)`** (plus retention); duplicates pruned by jobs.
- **`venues`**: one row per Resy `venue_id` seen; `last_drop_opened_at` updated on each emit.
- **`notify_preferences`**: rows per `recipient_id` × saved/excluded venue name (normalized).

---

## 5. Where to look in code

- Models: `backend/app/models/*.py`
- Poll + prune + compaction: `backend/app/services/discovery/buckets.py`
- Retention / scale notes: `backend/docs/SCALABILITY_AND_MAINTENANCE.md`

**Viewing diagrams:** GitHub renders Mermaid in this file. In VS Code / Cursor, use a Mermaid preview extension, or paste the fenced blocks into [mermaid.live](https://mermaid.live).

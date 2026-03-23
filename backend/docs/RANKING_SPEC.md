# Snag ranking spec (Task 3.1b) — Phase A

## Objective (“top”)

Order the home experience so the **first screenful** maximizes **actionable, trustworthy** openings: venues where a **diff-based** signal suggests the table **was not** trivially visible in the last poll, **still bookable now**, and **worth attention** (scarcity / demand proxies). We **do not** optimize for “most inventory.”

## Scored / tiered dimensions

| Dimension | Source | Role |
|-----------|--------|------|
| **Eligibility** | `drop_events.eligibility_evidence` + `successful_poll_count` | **Gate** weak / unknown / first-poll rows off primary boards (see `eligibility.py`). |
| **Recency** | `user_facing_opened_at` (via `detected_at` on cards) | Strong boost when &lt; 10–15 minutes in `_priority_score` / `_ticker_score`. |
| **Scarcity** | `rarity_score` (rolling metrics) | Scarcity multiplier on ranked / ticker. |
| **Demand proxy** | `avg_drop_duration_seconds`, `resy_popularity_score` | Speed + popularity bonuses. |
| **Editorial** | Hotspot list | `feedHot` and fixed bonuses. |

## Tradeoffs

1. **Gates before scores:** In `build_feed`, cards that are **only** weak just-opened signals are removed from ranked/ticker pools (see `_snag_excluded_from_ranked_board`).
2. **Tier multiplier:** Among qualifying cards, `rank_strength_multiplier(evidence)` down-ranks `empty_prev_delta` and `baseline_only` vs `nonempty_prev_delta`.
3. **Lexicographic intent:** Hotspots and top-opportunity picks remain **quality-first**; eligibility does not shuffle iconic venues below random noise.

## Tie-breakers

- Sort keys use stable floats then **venue id / name** (via consolidated card `id`) — no random shuffles.
- `sorted(..., key=...)` in `feed.py` is deterministic for equal scores.

## Failure-mode scenarios (regression targets)

1. **Unknown evidence + only just-opened:** must **not** appear as a primary ranked card.
2. **First poll bucket:** must **not** appear on ranked/ticker when it is the only source.
3. **Nonempty prev delta + hotspot:** must remain **above** a weak empty-prev unknown-quality venue when freshness is similar.
4. **Still-open-only card:** remains even if `snag_feed_qualified` is false.
5. **Push:** only `nonempty_prev_delta` / `empty_prev_delta` (see `push_notification_allowed`).

## Anti–analytics UI

This spec governs **server ordering** and **gates**. Do not add `%`, charts, or dashboard payloads for consumers.

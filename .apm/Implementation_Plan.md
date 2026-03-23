# paystub-service – APM Implementation Plan
**Memory Strategy:** Dynamic-MD
**Last Modification:** Amended by Setup Agent: product roadmap (experience phases A–D) and mapping to technical phases.
**Project Overview:** Evolve **Snag** (DropFeed) as a **drop-first** product: it does **not** compete on search, filters, or “browse what’s available” convenience like typical aggregators. The premise is that the **best** places are **already fully booked**; Snag **tracks unavailability**, then surfaces a venue **only when** something **briefly** becomes possible that **was not** possible before. That transition is the **value signal**—if it appears in Snag, it is not because it was easy to find; it is because it **was not gettable** before. Delivery is organized in **product experience phases A→D** (below): **A** nails the core home loop (**ranked** best opportunities, **not** a raw dump—**speed, clarity, trust**); **B–D** add personalization, intelligence, and **optional** power features **without** replacing that loop. Technically this requires a **credible “was fully booked, then opened”** model, a **14-day** horizon, rich **telemetry**, and **push**, with **Postgres first**, then FastAPI, ranking, and iOS. Success: **correctness** (no false positives), **tests passing**, solid implementation.

## Product principles (Snag vs search / convenience aggregators)

- **Not the same job as TableOne-style apps:** Those products optimize for **user-specified criteria**, **search**, **filtering**, and **aggregation** of what is already available; their value is **convenience** for someone who knows what they want.
- **Snag’s job:** The user opens the app to see **what just became possible**, not to query inventory. **Filtering and prioritization happen server-side**; the experience is **reactive** (act on opportunities), not **browsy** (construct a result set).
- **Primary surface:** The home experience is a **ranked set of the best opportunities** across the **next 14 days**, not a neutral list of “results” or everything available. Implementation and APIs should reinforce **opportunity ranking** and **eligibility truth**, not generic catalog browsing as the hero loop.
- **Canonical journey:** User **opens the app → immediately sees the best opportunities → recognizes value → acts**. Follows, alerts, predictions, and optional search/autopilot **support** that loop; they do **not** replace it.

## Product roadmap: experience phases (A → D)

These are **product** sequencing priorities (not the same numbering as technical phases below). **Do not** ship B–D at the expense of A.

### Phase A — Core product (priority: speed, clarity, trust)

- **Home is not a raw feed:** A **ranked** set of the **best** opportunities across the **next 14 days**, **high signal**, **immediate** feel.
- **Real time:** New drops should show up **live** (or near-live) with **obvious urgency** (e.g. copy/chip-like indicators such as **“opened seconds ago”**—driven by accurate server timestamps).
- **Frictionless action:** **One tap to book** (deep link / continue into the booking surface); **no** mandatory extra steps on the happy path.
- **Minimal decision support only:** Small number of **high-trust** signals—e.g. how fast a table **usually** disappears and a **demand** proxy—enough to decide fast, not analytics noise.

### Phase B — Personal and engaging (after A works)

- **Follows:** Users follow **specific** restaurants they care about (e.g. named hotspots); **simple** status surfaces—**last drop**, **likely activity soon** (honest, not spammy).
- **Smart notifications:** **Not generic**; alert when something **meaningful** (e.g. rare drop, likely to vanish quickly) using the same truth/ranking stack as the feed.
- **Lightweight activity view:** What they **missed** or **caught**—helps them **learn** how Snag behaves over time.

### Phase C — Intelligence (after B; uses data you already collect)

- **No dashboards:** Surface **simple, actionable** patterns—typical **release** cadence, **how often**, **how fast** tables get taken.
- **Lightweight predictions** (clearly labeled): e.g. **“likely to open tonight”**, **“higher activity than usual this week.”**
- **Ranking quality:** The **most important** lever—**top slots should consistently be the most valuable** opportunities, informed by telemetry.

### Phase D — Advanced / optional (only after A–C)

- **Search or refine tab:** For users who **want** date/time specificity—**explicitly secondary**; **not** the main experience.
- **Autopilot:** Passive tracking from **broad preferences**; notify **only** when something crosses a **high** worth-it bar.

### Mapping: product phases ↔ technical phases in this plan

| Product phase | Role of this plan |
|----------------|-------------------|
| **A** | **Technical Phases 1–6** are the primary delivery vehicle: schema → ingestion → truth/ranking → API/push → iOS home → QA. Task guidance below is tightened for **ranked home**, **freshness**, **one-tap book**, and **minimal signals**. |
| **B** | **Technical Phase 7** |
| **C** | **Technical Phase 8** |
| **D** | **Technical Phase 9** |

---

## Phase 1: Postgres schema and data-model foundation
**Agent domain:** `Agent_Backend_Data` — owns migrations, table design, indexes, backfills, and data-level invariants.

### Task 1.1 – Model and migration inventory – Agent_Backend_Data
**Objective:** Map the current ORM models and Alembic history to product entities (venues, sessions, slots, drops, metrics, notify) so refactors are intentional, not accidental.
**Output:** Written mapping (in task notes or PR description) from existing `app/models/*.py` and hot paths to target responsibilities; list of deprecated or redundant structures to fold or drop.
**Guidance:**
- Trace relationships across `slot_availability`, `availability_state`, `availability_session`, `drop_event`, `venue_*_metrics`, `feed_cache`, `discovery_*`, and notify/push tables.
- Flag tables or columns that cannot support a falsifiable “fully booked before open” narrative without new facts or timestamps.
- **Depends on:** None.

### Task 1.2 – Target schema and invariants – Agent_Backend_Data
**Objective:** Define the **target** relational design (keys, lifecycles, aggregate vs raw storage) that supports scan semantics, drop history, and ranking inputs without redundant divergent sources of truth.
**Output:** Agreed target shape (new/changed tables and columns) documented for implementers—enough that migrations and services can be implemented without reinterpretation.
**Guidance:**
- Encode explicit states or timestamps needed to prove **prior unavailability** at the right granularity (venue × date × slot bucket as appropriate).
- Prefer **additive** migrations and backward-compatible phases unless a breaking cut is unavoidable; call out cut points.
- Plan for **telemetry** fields used later by ranking (e.g. time-to-take, scan coverage, confidence)—store raw or rolled-up per performance targets.
- Include aggregates or rollups needed for **Product phase A** **minimal decision signals** (e.g. typical time-to-take, demand proxy) without turning the product into analytics-first.
- **Depends on: Task 1.1 Output**

### Task 1.3 – Alembic migrations – Agent_Backend_Data
**Objective:** Implement database changes for the target schema with a reversible or staged path suitable for production Postgres.
**Output:** New Alembic revision(s) applied cleanly on a copy of prod-like data; models updated to match.
**Guidance:**
- Keep revisions reviewable (avoid mixing unrelated concerns in one revision when it obscures rollback).
- Include constraints, uniqueness, and FK behavior needed for correctness under concurrent writers.
- **Depends on: Task 1.2 Output**

### Task 1.4 – Indexes and hot-path query optimization – Agent_Backend_Data
**Objective:** Ensure the feed, drop detection, and admin/debug queries use index-friendly predicates and stable plans.
**Output:** Added or adjusted indexes (including partial indexes where appropriate); notes on `EXPLAIN (ANALYZE)` for the agreed critical queries.
**Guidance:**
- Align with actual filter/sort columns used by `feed`-adjacent code paths after schema change (coordinate with Phase 3 consumer tasks).
- Avoid speculative indexes; tie each index to a concrete query or job.
- **Depends on: Task 1.3 Output**

### Task 1.5 – Backfill, data migration, and consistency checks – Agent_Backend_Data
**Objective:** Move or derive historical data into the new shape and verify row counts and key invariants.
**Output:** Idempotent backfill script(s) or SQL job(s) plus post-migration validation queries (and optional small Python checks in `backend/` tests or one-off tooling).
**Guidance:**
- Define “empty vs unknown vs fully booked” handling during backfill so ranking does not inherit garbage semantics.
- **Depends on: Task 1.3 Output** (can partially parallelize planning with Task 1.4 after 1.3 exists).

---

## Phase 2: Ingestion, scans, and service write/read paths
**Agent domain:** `Agent_Backend_Services` — FastAPI app services, jobs, repositories; not ranking policy.

### Task 2.1 – Persist scan results to the new schema – Agent_Backend_Services
**Objective:** Make all availability capture paths write **only** through the new model so downstream code has one source of truth.
**Output:** Updated ingestion/session/slot persistence aligned to Phase 1 tables; obsolete write paths removed or guarded.
**Guidance:**
- Enforce the **14-day** horizon at write or prune boundaries as agreed in Phase 1.
- Preserve enough raw history for telemetry without unbounded table growth (TTL, partition strategy, or rollups as per Phase 1).
- **Depends on: Task 1.3 Output by Agent_Backend_Data**

### Task 2.2 – Schedulers and job boundaries – Agent_Backend_Services
**Objective:** Align periodic scans, deduplication, and retries with the new storage semantics and operational limits.
**Output:** Job entrypoints and configuration documented in code; failure modes do not corrupt “prior state” invariants.
**Guidance:**
- Ensure idempotent writes where the same scan result may be replayed.
- **Depends on: Task 2.1 Output**

### Task 2.3 – Repository/read layer for consumers – Agent_Backend_Services
**Objective:** Provide stable, tested read accessors for feed/ranking/push code (filtered, paginated, keyed as needed).
**Output:** Functions or repository methods used by Phase 3–4 with unit tests on edge cases (no data, partial coverage).
**Guidance:**
- Avoid embedding ranking policy here—expose facts and cheap filters only.
- **Depends on: Task 2.1 Output**

---

## Phase 3: Drop truth, ranking, and feed correctness
**Agent domain:** `Agent_Ranking_Intelligence` — discovery feed assembly, scoring, eligibility, telemetry interpretation.

### Task 3.1 – Formal “fully booked before” definition – Agent_Ranking_Intelligence
**Objective:** Produce an **implementable specification** (predicates over stored facts) that matches the product thesis and eliminates ambiguous cases.
**Output:** Short spec embedded in code comments or module docstring plus checklist of edge cases (new venue, partial scan, API ambiguity, off-hours).
**Guidance:**
- Directly addresses the user’s top risk: **venues that were clearly not fully booked** must **not** qualify.
- Explicitly define what evidence **disqualifies** a drop (e.g. first observation, insufficient prior snapshots, conflicting slot signals).
- **Depends on: Task 2.1 Output by Agent_Backend_Services** (needs real persisted fields); conceptual work can start after **Task 1.2 Output by Agent_Backend_Data**.

### Task 3.2 – Scoring and gating implementation – Agent_Ranking_Intelligence
**Objective:** Implement the spec in `likely_open_scoring` (and related modules), with **unit tests** for disqualification and qualification paths.
**Output:** Code + tests; measurable reduction or elimination of false-positive scenarios covered by tests.
**Guidance:**
- Prefer explicit gates over opaque score tuning where possible so regressions are testable.
- **Depends on: Task 3.1 Output** and **Task 2.3 Output by Agent_Backend_Services**

### Task 3.3 – Feed assembly and API-facing narrative – Agent_Ranking_Intelligence
**Objective:** Update `feed.py` (and siblings) so ordering, deduplication, and card payloads reflect the new eligibility and telemetry.
**Output:** Feed behavior consistent with gates; integration-style tests or fixture-driven tests where the repo already patterns them.
**Guidance:**
- Ensure the feed never contradicts stored eligibility (if flagged not qualified, must not appear as a “true drop”).
- Shape the feed as **ranked opportunities** for Snag’s home loop—not a search-result or “available inventory” listing; ranking encodes **why this moment matters** (unavailable → briefly available).
- Optimize ordering for **high signal** and **trust** (best opportunities first), not a raw chronological dump of everything that moved.
- **Depends on: Task 3.2 Output**

### Task 3.4 – Telemetry hooks for debugging false positives – Agent_Ranking_Intelligence
**Objective:** Log or expose **structured** diagnostics (at appropriate verbosity) to explain why a venue qualified or failed—without PII leakage.
**Output:** Debug fields or logs usable in staging; optional admin-only JSON on feed items if already a pattern in the API.
**Guidance:**
- Tie fields to the predicates from Task 3.1 for traceability.
- **Depends on: Task 3.2 Output**

---

## Phase 4: HTTP APIs and push pipeline
**Agent domain:** `Agent_Backend_Services`

### Task 4.1 – Feed and discovery API contract updates – Agent_Backend_Services
**Objective:** Serialize new fields needed by iOS (eligibility reasons, timestamps, confidence) while maintaining backward compatibility or versioning if required.
**Output:** Updated Pydantic schemas/routes; contract matches Phase 3 outputs.
**Guidance:**
- Coordinate field names with **Task 5.1 Output by Agent_iOS** if strict coupling; otherwise choose stable names and document in OpenAPI.
- Contract should reflect **one ranked opportunity stream** for the primary experience (Snag home), not an aggregator-style “query then browse” API as the core metaphor.
- Support **Product phase A** **freshness:** precise **`opened_at` (or equivalent)** for client-relative urgency (“seconds ago”), and a practical **real-time or near-real-time** update story (efficient polling with cursors, push-triggered refresh, or streaming—choose what fits the stack without over-engineering).
- Payloads should carry the **small set** of **minimal signals** agreed for phase A (e.g. typical disappearance speed, demand proxy)—no dashboard sprawl.
- **Depends on: Task 3.3 Output by Agent_Ranking_Intelligence**

### Task 4.2 – Push notification eligibility – Agent_Backend_Services
**Objective:** Ensure push sends only when **the same eligibility rules** as the feed (or stricter) are satisfied, using `push` services and drop lifecycle.
**Output:** Updated push path with tests; no notifications for false-positive-class cases covered in Phase 3 tests.
**Guidance:**
- Reuse shared helper predicates from ranking layer if possible to avoid drift (**Depends on: Task 3.2 Output by Agent_Ranking_Intelligence**).
- For **Product phase A**, pushes may be **simpler** than Phase B “smart” policies; still avoid **generic noise**—tie to real new eligible opportunities. (Phase 7 refines **meaning-aware** alerting.)
- **Depends on: Task 4.1 Output**

---

## Phase 5: iOS client alignment
**Agent domain:** `Agent_iOS`

### Task 5.1 – Models and networking – Agent_iOS
**Objective:** Parse new API fields in Swift models and propagate through the data layer used by the feed.
**Output:** Compiling client with updated Codable/API layer; graceful handling of missing fields during rollout if server lags.
**Guidance:**
- **Depends on: Task 4.1 Output by Agent_Backend_Services**

### Task 5.2 – Feed UI and copy – Agent_iOS
**Objective:** Present the **home** experience as **ranked best opportunities** over the **14-day** window: **immediate**, **high signal**, **not a raw feed**. User **reacts** to what became possible; copy and hierarchy communicate **was not gettable → now briefly is**.
**Output:** Updated `FeedView` (and related views) reflecting new fields; UX consistent with existing design language and Snag principles above.
**Guidance:**
- Avoid treating the home surface like **search results** or **filter-first**; **prioritization is implicit** in ranking (background), aligned with backend order and signals.
- **Urgency:** Show **freshness** from server timestamps (e.g. **“opened seconds ago”** patterns) so value feels **live**.
- **Frictionless action:** Primary path is **one tap to book** (deep link / handoff into booking)—**no** extra mandatory steps on the happy path.
- **Minimal signals:** Surface only the agreed **small** set (e.g. typical time-to-take, demand) to support fast decisions—no clutter.
- **Real-time feel:** Coordinate with Task 4.1’s refresh strategy so **new** eligible drops appear **quickly** without draining battery (polling interval, push nudge, or both).
- **Depends on: Task 5.1 Output**

### Task 5.3 – Push handling – Agent_iOS
**Objective:** Deep links or in-app presentation align with new notification payload semantics.
**Output:** Verified handling on device/simulator for representative payloads.
**Guidance:**
- **Depends on: Task 4.2 Output by Agent_Backend_Services** and **Task 5.1 Output**

---

## Phase 6: Integration, tests, and ship readiness
**Agent domain:** `Agent_Quality` — cross-cutting verification; may pull in other agents for fixes.

### Task 6.1 – End-to-end and regression tests – Agent_Quality
**Objective:** Cover the critical path: scan → persist → rank → API → client representation for at least one golden scenario and one disqualification scenario.
**Output:** Automated tests (backend-focused minimum; iOS UI tests optional per repo norms) that fail if false-positive gates regress.
**Guidance:**
- Include checks that the home experience behaves as **ranked opportunities**, not an unranked/raw dump, where testable without brittle UI coupling.
- **Depends on: Task 3.2 Output by Agent_Ranking_Intelligence**, **Task 4.2 Output by Agent_Backend_Services**, **Task 5.2 Output by Agent_iOS**

### Task 6.2 – Production verification checklist – Agent_Quality
**Objective:** Short, repeatable checklist for deploy: migrations, job health, sample feed spot-check, push smoke—executable by the team without new process overhead.
**Output:** Checklist in PR template comment or existing ops doc **only if** the repo already has a home for runbooks; otherwise keep as task comment for Manager Agent.
**Guidance:**
- User preference: no extra documentation sprawl—keep this minimal.
- **Depends on: Task 6.1 Output**

---

## Phase 7: Personalization and engagement (Product phase B)
**Agent domains:** `Agent_Backend_Services`, `Agent_iOS` — **only after Product phase A** (Technical Phases 1–6) is in good shape.

### Task 7.1 – Follows, venue status, and activity APIs – Agent_Backend_Services
**Objective:** Let users **follow specific restaurants** and retrieve **simple status** (e.g. last drop, hints of likely near-term activity) plus data for a **lightweight activity** history (caught/missed) without duplicating a second ranking engine.
**Output:** Endpoints and persistence (or reuse of existing watch/follow tables if appropriate) with tests; contracts documented for iOS.
**Guidance:**
- Prefer **honest, sparse** status over noisy engagement gimmicks; align language with ranking confidence.
- **Depends on: Task 4.1 Output** (stable core feed contract patterns).

### Task 7.2 – Follows, status, and activity UI – Agent_iOS
**Objective:** Ship follow UX, **readable** per-venue status, and an **activity** surface so users learn how Snag behaves over time.
**Output:** Compiling UI wired to Task 7.1; consistent with Snag visual language.
**Guidance:**
- This **supports** the core open→see→act loop; it must not become the primary screen at the expense of home.
- **Depends on: Task 7.1 Output by Agent_Backend_Services**

### Task 7.3 – Meaning-aware notification policy – Agent_Backend_Services
**Objective:** Notifications that are **smart, not generic**—e.g. emphasize **rare** or **fast-vanishing** opportunities using ranking/telemetry inputs.
**Output:** Policy implementation in push pipeline with tests; configurable thresholds as needed.
**Guidance:**
- **Depends on: Task 7.1 Output** and **Task 3.2 Output by Agent_Ranking_Intelligence**

---

## Phase 8: Intelligence layer (Product phase C)
**Agent domains:** `Agent_Ranking_Intelligence`, `Agent_Backend_Services`, `Agent_iOS` — uses data already collected; **no** heavy analytics dashboards.

### Task 8.1 – Actionable patterns and lightweight predictions – Agent_Ranking_Intelligence
**Objective:** From stored telemetry, derive **simple, actionable** insights (typical release windows, frequency, time-to-take) and **lightly labeled** predictions (e.g. likely open tonight, higher activity than usual this week).
**Output:** Deterministic or well-bounded scoring/textual signals suitable for cards—not a BI dashboard.
**Guidance:**
- **Ranking improvement is central:** use the same facts to push **top opportunities** toward **maximum user value**.
- **Depends on: Task 3.2 Output** and stable telemetry from earlier phases.

### Task 8.2 – Insights API and integration – Agent_Backend_Services
**Objective:** Expose Task 8.1 outputs on relevant endpoints (feed enrichment, detail, or small insight payloads) with versioning discipline.
**Output:** API changes + tests; iOS-ready field names.
**Guidance:**
- **Depends on: Task 8.1 Output by Agent_Ranking_Intelligence**

### Task 8.3 – Client insight surfaces – Agent_iOS
**Objective:** Present insights/predictions **sparingly** on cards or detail—support quick decisions, not deep analysis screens.
**Output:** Updated UI consuming Task 8.2.
**Guidance:**
- **Depends on: Task 8.2 Output by Agent_Backend_Services**

---

## Phase 9: Optional advanced surfaces (Product phase D)
**Agent domains:** `Agent_Backend_Services`, `Agent_iOS` — **explicitly secondary**; ship only after A–C are solid.

### Task 9.1 – Secondary search/refine API – Agent_Backend_Services
**Objective:** Support users who want **time/date specificity** via an **optional** query path—not the hero ranked stream.
**Output:** Parameterized search/refine endpoint(s) with guardrails (rate limits, clarity that this is not “main Snag”).
**Guidance:**
- **Depends on: Task 4.1 Output**

### Task 9.2 – Search/refine tab (non-primary) – Agent_iOS
**Objective:** A **separate** entry point for refine/search; home remains **ranked opportunities first**.
**Output:** New tab or screen group per design; does not hijack launch experience.
**Guidance:**
- **Depends on: Task 9.1 Output by Agent_Backend_Services**

### Task 9.3 – Autopilot preferences and notify thresholding – Agent_Backend_Services
**Objective:** **Passive** tracking from broad preferences; notify **only** when an opportunity clears a **high** worth-it bar (reuse ranking/value signals).
**Output:** Preference storage + evaluation job hooks + tests.
**Guidance:**
- **Depends on: Task 8.1 Output by Agent_Ranking_Intelligence** (or **Task 3.2** if Phase 8 is not yet built—Manager may sequence; prefer 8.1 for richer thresholds).

### Task 9.4 – Autopilot UI – Agent_iOS
**Objective:** Simple controls for autopilot mode and expectations (“we only ping when it’s worth it”).
**Output:** UI wired to Task 9.3.
**Guidance:**
- **Depends on: Task 9.3 Output by Agent_Backend_Services**

---

## Plan metadata (for Manager Agent)
| Agent | Domain | Task count (approx.) |
|--------|--------|------------------------|
| Agent_Backend_Data | Postgres schema, migrations, indexes, backfill | 5 |
| Agent_Backend_Services | Ingestion, jobs, repos, API, push, personalization APIs, insights API, optional search/autopilot | 10 |
| Agent_Ranking_Intelligence | Eligibility, scoring, feed, telemetry, insights/predictions | 5 |
| Agent_iOS | Core home, push, personalization UI, insights UI, optional tab/autopilot | 7 |
| Agent_Quality | E2E/regression, ship checklist | 2 |
| **Total** | | **29** |

**Technical phases:** 9 (Phases 1–6 = **Product A** core; 7–9 = **Product B–D**).  
**Cross-agent dependencies:** Multiple explicit `Depends on: Task X.Y … by Agent_*` links above (feed/ranking/services/iOS boundary).

**Context synthesis anchors embedded:** schema-first sequencing; full-stack scope; false-positive “fully booked” as primary correctness risk; ship when tests and quality are good; **Snag ≠ search/convenience aggregator**; **ranked 14-day home**, **reactive** loop; **product phases A→D** with **B–D supporting, not replacing**, A; **optional** search/autopilot only in Phase 9.

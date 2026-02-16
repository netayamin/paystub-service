# OOP Design Principles in This Backend

This document maps the [10 OOP design principles](https://hackernoon.com/10-oop-design-principles-every-programmer-should-know-f187436caf65) to how we apply them in the Python/FastAPI backend. The goal is **high cohesion, low coupling**, and code that is easy to test, debug, and extend.

---

## 1. DRY (Don’t Repeat Yourself)

**Principle:** Don’t duplicate code; abstract common logic into one place. Duplication is about **functionality**: don’t share code for two unrelated behaviors (e.g. OrderId vs SSN validation) just because they look similar.

**In this codebase:**
- **Routes:** Shared behavior (e.g. parse `since` ISO, get next scan time) lives in small helpers or `api/deps.py` so route handlers stay thin.
- **Services:** Discovery logic lives in `services/discovery/` (buckets, scan); Resy in `services/resy/`. No copy-paste of the same flow in multiple places.
- **Constants:** Discovery window, time slots, timeouts are defined once in `services/discovery/buckets.py` (and scan.py for heartbeat thresholds).

---

## 2. Encapsulate What Changes

**Principle:** Hide the code that is likely to change behind a stable interface. Use private-by-default (e.g. `_helper`) and expose only what callers need.

**In this codebase:**
- **Config:** `app/config.py` holds all env-derived settings; changing a key or default happens in one place.
- **Resy client:** `services/resy/` encapsulates HTTP and config; the rest of the app uses `search_with_availability()` and does not touch URLs or headers.
- **Discovery constants:** `WINDOW_DAYS`, `TIME_SLOTS`, `FETCH_TIMEOUT_SECONDS`, etc. are in discovery modules; changing the 14-day window or slots does not scatter edits across routes.
- **Scheduler job IDs:** Job names like `"discovery_bucket"` are used in one place (main.py) and in discovery’s “next run” helper; if we ever change them, we keep that localized.

---

## 3. Open Closed (Open for Extension, Closed for Modification)

**Principle:** Add new behavior by extending (new modules, new functions) rather than editing existing, working code.

**In this codebase:**
- **New routes:** New endpoints go into the appropriate route module (`chat.py`, `discovery.py`, `resy.py`) or a new router; we don’t rewrite existing handlers.
- **New agents/tools:** New agents go in `agents/`, new tools in `toolsets/`; they are registered in the orchestrator/toolset without changing the core run loop.
- **New jobs:** New scheduler jobs are new modules in `scheduler/` and one line in `main.py`; existing jobs stay untouched.
- **New providers:** If we add another “availability” provider besides Resy, we’d add a new client/service and call it from discovery/orchestrator behind an interface, rather than editing Resy code.

---

## 4. Single Responsibility Principle (SRP)

**Principle:** One reason to change per class/module. One clear responsibility per component.

**In this codebase:**
- **Routes:** `chat.py` = chat/sessions/watches/availability/admin; `discovery.py` = feed/health/debug; `resy.py` = legacy watch list. Each file has one “axis” of change.
- **Services:** `chat_session_service` = messages + last venue search; `venue_watch_service` = interval watches; `venue_notify_service` = notify-when-available; `discovery/buckets.py` = bucket/drop pipeline; `discovery/scan.py` = heartbeat + fast checks. No “god” service.
- **Models:** One model per table; no business logic in models.
- **Scheduler:** Each job file does one job (e.g. `discovery_bucket_job` only runs the bucket pipeline).

---

## 5. Dependency Injection / Inversion

**Principle:** Don’t create dependencies inside the component; receive them from outside (constructor, function args, or framework). Improves testability and keeps object creation centralized.

**In this codebase:**
- **FastAPI `Depends()`:** All route handlers receive `db: Session = Depends(get_db)`. The app provides the session; routes don’t call `SessionLocal()`.
- **Orchestrator:** Receives `db`, `session_id`, `message_history`; it doesn’t open DB connections itself.
- **Agents/tools:** Receive `RunContext[ResyDeps]` with `db`, `session_id`, etc.; they don’t import `get_db` or create sessions.
- **Jobs:** Create their own `SessionLocal()` in the job function and close it in `finally`; the scheduler only invokes the function. For heavier DI we could inject a session factory.

---

## 6. Favor Composition over Inheritance

**Principle:** Prefer composing behavior (e.g. passing in a dependency or using a small helper) over deep inheritance hierarchies.

**In this codebase:**
- **No deep class trees:** We use functions and modules rather than big base classes. “Behavior” is composed by calling services from routes, tools from agents, and services from tools.
- **Discovery:** The bucket pipeline composes “fetch,” “baseline,” “poll,” “emit drops” as steps and functions, not subclasses.
- **Resy:** `ResyClient` is used inside `search_with_availability`; we don’t subclass it for different search types.

---

## 7. Liskov Substitution Principle (LSP)

**Principle:** Subtypes must be substitutable for their base type; callers that depend on the base type must work with any implementation without surprises.

**In this codebase:**
- **Protocols/ABCs:** Where we introduce an abstract type (e.g. “availability provider”), implementations must honor the same contract (same method names and semantics). We don’t yet have formal Protocol classes for Resy vs a hypothetical second provider, but when we do, LSP will guide the interface.
- **Models:** SQLAlchemy model subclasses are used as declared; we don’t override methods in a way that breaks callers expecting the base behavior.

---

## 8. Interface Segregation Principle (ISP)

**Principle:** Clients should not depend on interfaces they don’t use. Prefer small, focused interfaces over one large one.

**In this codebase:**
- **Route modules:** Chat routes don’t depend on discovery; discovery routes don’t depend on chat. Each router only imports what it needs.
- **Services:** Callers import specific functions (`get_feed`, `get_bucket_health`) rather than a single “DiscoveryService” with many methods they don’t use.
- **Tools:** Each tool has a narrow contract (e.g. search, start watch, notify); the agent doesn’t receive one huge “Resy API” interface.

---

## 9. Program to Interface, Not Implementation

**Principle:** Depend on abstractions (interfaces, protocols, abstract types) in variables, return types, and arguments so behavior can be swapped without changing callers.

**In this codebase:**
- **Typing:** We use `Session` from SQLAlchemy (the interface to the DB), not a concrete implementation detail. Return types are typed (e.g. `list[dict]`, `dict`) so callers rely on shape, not a specific class.
- **Resy:** The rest of the app depends on `search_with_availability(day, party_size, ...)` returning a dict with `venues`/`error`; the actual HTTP client is an implementation detail inside `services/resy/`.
- **Future:** If we add a second availability source, we’d introduce a small protocol (e.g. “returns list of slots”) and have both Resy and the new source implement it; discovery would depend on that protocol.

---

## 10. Delegation

**Principle:** Don’t do everything in one place; delegate to the component responsible for that concern.

**In this codebase:**
- **Routes** delegate to services and orchestrator; they don’t contain business logic or SQL.
- **Orchestrator** delegates to the right agent and deps factory; it doesn’t implement chat logic.
- **Agents** delegate to tools; tools delegate to services.
- **Services** delegate to the DB (via models/session), Resy client, or discovery buckets. Equality/formatting is delegated to the right layer (e.g. `slot_id()` in buckets, datetime handling in one place).

---

## Summary Table

| Principle | How we apply it |
|-----------|------------------|
| **DRY** | Shared helpers, single place for constants and discovery/Resy flows. |
| **Encapsulate what changes** | Config, Resy client, discovery constants, job IDs. |
| **Open Closed** | New routes/jobs/agents by addition, not by editing existing code. |
| **SRP** | One responsibility per route module, service, job, model. |
| **Dependency Injection** | FastAPI `Depends(get_db)`, orchestrator and tools receive deps. |
| **Composition over inheritance** | Functions and composition; no deep inheritance. |
| **LSP** | Consistent contracts when we introduce protocols/implementations. |
| **ISP** | Small, focused route and service surfaces; narrow tool contracts. |
| **Program to interface** | Depend on Session, dict shapes, and high-level service APIs. |
| **Delegation** | Routes → services/orchestrator; tools → services; no “god” handlers. |

When adding or refactoring code, prefer these principles so the backend stays **cohesive and loosely coupled**, and remains easy to test and maintain.

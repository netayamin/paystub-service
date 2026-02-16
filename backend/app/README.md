# App structure

Clean layout by layer and domain. **No chat/agent** — watches, discovery, and Resy only.

| Layer | Purpose |
|-------|--------|
| **api/routes** | HTTP only. One file per domain: `watches`, `discovery`, `resy`. |
| **core** | Config, errors, constants. |
| **db** | SQLAlchemy base and session. |
| **models** | One ORM model per table. |
| **services** | All business logic and I/O. Domain subpackages: `discovery/`, `resy/`. |
| **scheduler** | Cron/interval jobs; each calls services with its own DB session. |
| **data** | Static/seed data (no DB). |

**Where to add things**

- New **HTTP endpoint** → `api/routes/<domain>.py` (watches, discovery, or resy).
- New **business logic** → `services/` (new file or under `services/<domain>/`).
- New **background job** → `scheduler/<name>_job.py` and register in `main.py`.

See **docs/ARCHITECTURE.md** for request flow and details.

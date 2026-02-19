"""
FastAPI app entrypoint.

Primary: Discovery (14-day drops). No chat/agent.
"""
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

# Load .env from backend/ before any app code
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

# Maxim AI: instrument Pydantic AI for tracing/evaluation before any agent is created
_maxim_api_key = os.getenv("MAXIM_API_KEY")
_maxim_repo_id = os.getenv("MAXIM_LOG_REPO_ID")
_maxim_logger = None
if _maxim_api_key and _maxim_repo_id:
    from maxim import Maxim
    from maxim.logger.pydantic_ai import instrument_pydantic_ai

    _maxim = Maxim({"api_key": _maxim_api_key})
    _maxim_logger = _maxim.logger({"id": _maxim_repo_id})
    instrument_pydantic_ai(_maxim_logger, debug=os.getenv("MAXIM_DEBUG", "").lower() in ("1", "true", "yes"))

from app.api.routes import discovery, notifications, resy
from app.config import settings
from app.core.constants import (
    DISCOVERY_BUCKET_JOB_ID,
    DISCOVERY_POLL_INTERVAL_SECONDS,
    DISCOVERY_SLIDING_WINDOW_JOB_ID,
)
from app.scheduler.discovery_bucket_job import run_discovery_bucket_job, run_sliding_window_job
from app.scheduler.hourly_resy import run_hourly_check

if settings.openai_api_key:
    os.environ["OPENAI_API_KEY"] = settings.openai_api_key

logger = logging.getLogger(__name__)

# Scheduler: run Resy watch list check every hour
_scheduler = BackgroundScheduler()


@asynccontextmanager
async def lifespan(app: FastAPI):
    import threading

    _scheduler.add_job(run_hourly_check, "interval", hours=1, id="resy_hourly")
    _scheduler.add_job(
        run_discovery_bucket_job,
        "interval",
        seconds=DISCOVERY_POLL_INTERVAL_SECONDS,
        id=DISCOVERY_BUCKET_JOB_ID,
    )
    _scheduler.add_job(
        run_sliding_window_job,
        "cron",
        hour=7,
        minute=5,
        id=DISCOVERY_SLIDING_WINDOW_JOB_ID,
    )
    _scheduler.start()
    app.state.scheduler = _scheduler

    def startup_background():
        # One tick on startup (prune, ensure buckets, baseline if needed, dispatch up to 8 ready buckets).
        try:
            run_discovery_bucket_job()
            logger.info("Discovery bucket job tick on startup; next tick in %ss", DISCOVERY_POLL_INTERVAL_SECONDS)
        except Exception as e:
            logger.warning("Discovery bucket job on startup failed: %s", e, exc_info=True)

    threading.Thread(target=startup_background, daemon=True).start()
    print("\n" + "=" * 60)
    print("  BACKEND READY  http://127.0.0.1:8000")
    print("  API docs       http://127.0.0.1:8000/docs")
    print("  Health         http://127.0.0.1:8000/health")
    print("=" * 60 + "\n")
    logger.info("Backend ready at http://127.0.0.1:8000")
    yield
    _scheduler.shutdown(wait=False)


app = FastAPI(title="Resy Discovery", version="0.1.0", lifespan=lifespan)

# CORS: dev origins + optional CORS_ORIGINS env (comma-separated) for production frontend, e.g. https://your-app.vercel.app
_cors_origins = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:4173",
    "http://127.0.0.1:4173",
]
_cors_extra = os.getenv("CORS_ORIGINS", "")
if _cors_extra:
    _cors_origins.extend(o.strip() for o in _cors_extra.split(",") if o.strip())
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if _maxim_logger is not None:
    app.state.maxim_logger = _maxim_logger

    @app.middleware("http")
    async def flush_maxim_after_request(request, call_next):
        response = await call_next(request)
        try:
            maxim_logger = getattr(app.state, "maxim_logger", None)
            if maxim_logger:
                maxim_logger.flush()
        except Exception:
            pass
        return response

app.include_router(discovery.router, prefix="/chat", tags=["discovery"])
app.include_router(notifications.router, prefix="/chat", tags=["notifications"])
app.include_router(resy.router, prefix="/resy", tags=["resy"])


_STATIC_DIR = Path(__file__).resolve().parent / "static"


@app.get("/chat-ui", include_in_schema=False)
def chat_test_ui():
    """Simple test chat UI (alternative to Swagger)."""
    return FileResponse(_STATIC_DIR / "chat_test.html", media_type="text/html")


@app.get("/", include_in_schema=False)
def root():
    """Root: point to API docs and health."""
    return {"message": "Resy API", "docs": "/docs", "health": "/health"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

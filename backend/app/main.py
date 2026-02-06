"""
FastAPI app entrypoint: Resy booking agent + hourly watch list check.
"""
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv
from fastapi import FastAPI
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

from app.api.routes import chat, resy
from app.config import settings
from app.scheduler.hourly_resy import run_hourly_check
from app.scheduler.venue_watch_job import run_venue_watch_checks
from app.scheduler.venue_notify_job import run_venue_notify_checks_job

if settings.openai_api_key:
    os.environ["OPENAI_API_KEY"] = settings.openai_api_key

logger = logging.getLogger(__name__)

# Scheduler: run Resy watch list check every hour
_scheduler = BackgroundScheduler()


@asynccontextmanager
async def lifespan(app: FastAPI):
    _scheduler.add_job(run_hourly_check, "interval", hours=1, id="resy_hourly")
    _scheduler.add_job(run_venue_watch_checks, "interval", minutes=1, id="venue_watch")
    _scheduler.add_job(run_venue_notify_checks_job, "interval", minutes=1, id="venue_notify")
    _scheduler.start()
    yield
    _scheduler.shutdown(wait=False)


app = FastAPI(title="Resy Booking Agent", version="0.1.0", lifespan=lifespan)

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

app.include_router(chat.router, prefix="/chat", tags=["chat"])
app.include_router(resy.router, prefix="/resy", tags=["resy"])


_STATIC_DIR = Path(__file__).resolve().parent / "static"


@app.get("/chat-ui", include_in_schema=False)
def chat_test_ui():
    """Simple test chat UI (alternative to Swagger)."""
    return FileResponse(_STATIC_DIR / "chat_test.html", media_type="text/html")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

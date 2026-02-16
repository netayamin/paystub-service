# Backend for paystub-service (FastAPI + discovery). Run with docker-compose next to Postgres.
FROM python:3.11-slim

WORKDIR /app

# Install Poetry and system deps (for psycopg2 if needed)
RUN pip install --no-cache-dir poetry && \
    apt-get update && apt-get install -y --no-install-recommends libpq-dev gcc && \
    rm -rf /var/lib/apt/lists/*

# Copy dependency files first for better layer caching
COPY pyproject.toml poetry.lock* ./

# Install dependencies (no dev)
RUN poetry config virtualenvs.create false && poetry install --without dev --no-interaction --no-root

# Copy application
COPY . .

RUN chmod +x scripts/wait-for-db.sh 2>/dev/null || true

# Run as non-root
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Compose overrides with: wait-for-db && alembic upgrade head && uvicorn ...
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]

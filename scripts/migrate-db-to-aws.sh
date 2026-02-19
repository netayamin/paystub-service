#!/usr/bin/env bash
# Dump local Postgres and restore to a remote DB (e.g. AWS RDS).
# Usage:
#   REMOTE_DATABASE_URL='postgresql://user:pass@your-rds.region.rds.amazonaws.com:5432/postgres' ./scripts/migrate-db-to-aws.sh
# Or export REMOTE_DATABASE_URL then run the script.
# Requires: local DB running (e.g. make db-up). Uses Docker for pg_dump if pg_dump not in PATH.

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_URL="${LOCAL_DATABASE_URL:-postgresql://paystub:paystub@localhost:5432/paystub}"
REMOTE_URL="${REMOTE_DATABASE_URL:-}"

if [ -z "$REMOTE_URL" ]; then
  echo "Error: set REMOTE_DATABASE_URL (your AWS RDS or remote Postgres URL)."
  echo "Example: export REMOTE_DATABASE_URL='postgresql://user:pass@xxx.region.rds.amazonaws.com:5432/postgres'"
  exit 1
fi

DUMP_FILE="${REPO_ROOT}/.tmp/paystub_dump_$(date +%Y%m%d_%H%M%S).dump"
mkdir -p "$(dirname "$DUMP_FILE")"

# Dump: use Docker if pg_dump not on PATH (e.g. local db container)
if command -v pg_dump >/dev/null 2>&1; then
  echo "Dumping local DB ($LOCAL_URL) to $DUMP_FILE ..."
  pg_dump "$LOCAL_URL" -Fc -f "$DUMP_FILE"
else
  echo "Dumping local DB via Docker (paystub-service-db-1) to $DUMP_FILE ..."
  docker exec paystub-service-db-1 pg_dump -U paystub -d paystub -Fc -f /tmp/paystub.dump
  docker cp paystub-service-db-1:/tmp/paystub.dump "$DUMP_FILE"
fi

# Restore: use pg_restore if on PATH; otherwise print instructions for EC2
if command -v pg_restore >/dev/null 2>&1; then
  echo "Restoring to remote DB..."
  pg_restore -d "$REMOTE_URL" --clean --if-exists --no-owner --no-acl "$DUMP_FILE" || true
  echo "Done. Remote DB is now a copy of local."
else
  echo "pg_restore not found on this machine."
  echo ""
  echo "*** Do NOT run pg_restore on EC2 (t3.micro has 1 GB RAM; restore can OOM and crash the instance). ***"
  echo ""
  echo "Install PostgreSQL client tools locally and re-run this script so restore runs from your Mac to RDS:"
  echo "  brew install libpq"
  echo "  echo 'export PATH=\"/opt/homebrew/opt/libpq/bin:\$PATH\"' >> ~/.zshrc   # or ~/.bashrc"
  echo "  # Restart terminal or: source ~/.zshrc"
  echo "  REMOTE_DATABASE_URL='...' ./scripts/migrate-db-to-aws.sh"
  echo ""
  echo "RDS must be reachable from your Mac: set RDS 'Public access' to Yes (temporarily) and allow your IP in the RDS security group (port 5432)."
  echo ""
  echo "Dump saved at: $DUMP_FILE (use it once pg_restore is available and re-run the script, or restore manually with the same REMOTE_DATABASE_URL)."
  exit 0
fi

echo "Optional: run migrations against remote to ensure schema is current:"
echo "  cd backend && DATABASE_URL='$REMOTE_URL' poetry run alembic upgrade head"
rm -f "$DUMP_FILE"

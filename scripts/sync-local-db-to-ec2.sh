#!/usr/bin/env bash
# Dump local Postgres and show how to restore it into the DB running on EC2 (Docker).
# Use this when your EC2 DB is not exposed on port 5432 (default production setup).
#
# Usage: ./scripts/sync-local-db-to-ec2.sh
# Then follow the printed instructions (scp dump to EC2, then run restore commands on EC2).

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_URL="${LOCAL_DATABASE_URL:-postgresql://paystub:paystub@localhost:5432/paystub}"
DUMP_FILE="${REPO_ROOT}/.tmp/paystub_sync.dump"

mkdir -p "$(dirname "$DUMP_FILE")"

echo "==> Dumping local DB to $DUMP_FILE ..."
if command -v pg_dump >/dev/null 2>&1; then
  pg_dump "$LOCAL_URL" -Fc -f "$DUMP_FILE"
else
  # Postgres only in Docker: run pg_dump from the db container
  if docker compose -f "$REPO_ROOT/docker-compose.yml" ps -q db 2>/dev/null | grep -q .; then
    docker compose -f "$REPO_ROOT/docker-compose.yml" exec -T db pg_dump -U paystub -d paystub -Fc > "$DUMP_FILE"
  else
    echo "Error: local DB not running. Start it with: make db-up"
    echo "Or install PostgreSQL client (brew install libpq) so pg_dump is available."
    exit 1
  fi
fi
echo ""

echo "==> Next steps: copy this dump to your EC2 and restore into the Postgres container."
echo "    IMPORTANT: On EC2, stop the backend BEFORE restore so the instance does not overload (t3.micro)."
echo ""
echo "1. Copy dump to EC2 (replace EC2_IP and key/user as needed):"
echo "   scp -i your-key.pem $DUMP_FILE ec2-user@EC2_IP:~/paystub_sync.dump"
echo ""
echo "2. On EC2: STOP THE BACKEND FIRST (so restore does not overload the instance):"
echo "   ssh -i your-key.pem ec2-user@EC2_IP"
echo "   cd paystub-service"
echo "   sudo docker-compose -f docker-compose.prod.yml stop backend"
echo ""
echo "3. Copy dump into db container and do a CLEAN restore (drop DB, create, restore):"
echo "   sudo docker-compose -f docker-compose.prod.yml cp ~/paystub_sync.dump db:/tmp/paystub_sync.dump"
echo "   sudo docker-compose -f docker-compose.prod.yml exec db psql -U paystub -d postgres -c \"DROP DATABASE IF EXISTS paystub;\""
echo "   sudo docker-compose -f docker-compose.prod.yml exec db psql -U paystub -d postgres -c \"CREATE DATABASE paystub OWNER paystub;\""
echo "   sudo docker-compose -f docker-compose.prod.yml exec db pg_restore -U paystub -d paystub --no-owner --no-acl /tmp/paystub_sync.dump"
echo "   sudo docker-compose -f docker-compose.prod.yml exec db rm -f /tmp/paystub_sync.dump"
echo ""
echo "4. Start the backend again:"
echo "   sudo docker-compose -f docker-compose.prod.yml up -d backend"
echo ""
echo "5. On EC2, ensure backend/.env has valid Resy credentials (RESY_API_KEY, RESY_AUTH_TOKEN)."
echo "   Edit with: nano backend/.env  (or scp from local). Then: sudo docker-compose -f docker-compose.prod.yml up -d backend"
echo ""
echo "6. If SSH times out (banner exchange) or instance is unresponsive: reboot instance from"
echo "   AWS Console, wait 3-5 min, try again. See docs/EC2_SSH_RECOVERY.md for full steps."
echo ""
echo "Dump file kept at: $DUMP_FILE"

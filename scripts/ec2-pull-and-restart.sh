#!/bin/bash
# On EC2: pull latest, run migrations, restart Docker (no build).
# Run this script ON THE EC2 SERVER (e.g. after SSH in), or pass commands via SSH from your Mac.
# Usage on EC2: bash scripts/ec2-pull-and-restart.sh
set -e
cd ~/paystub-service
echo "==> Pulling origin main..."
git pull origin main
echo "==> Running migrations (in Docker)..."
if command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE="sudo docker-compose"
else
  DOCKER_COMPOSE="sudo docker compose"
fi
$DOCKER_COMPOSE -f docker-compose.prod.yml run --rm backend alembic upgrade head || true
echo "==> Restarting Docker (no build)..."
$DOCKER_COMPOSE -f docker-compose.prod.yml up -d
$DOCKER_COMPOSE -f docker-compose.prod.yml ps
echo "Done. Remember to set NOTIFICATION_EMAIL and SMTP_APP_PASSWORD in backend/.env for email alerts."

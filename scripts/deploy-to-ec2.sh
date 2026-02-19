#!/bin/bash
# Deploy to EC2: SSH in and run git pull + docker compose up. For first-time setup, run ec2-bootstrap.sh on the server.
# Usage:
#   EC2_KEY=/path/to/your-key.pem ./scripts/deploy-to-ec2.sh
#   ./scripts/deploy-to-ec2.sh /path/to/your-key.pem
set -e

EC2_HOST="${EC2_HOST:-18.118.55.231}"
KEY="${EC2_KEY:-$1}"

if [ -z "$KEY" ] || [ ! -f "$KEY" ]; then
  echo "Usage: EC2_KEY=/path/to/your-key.pem $0"
  echo "   or: $0 /path/to/your-key.pem"
  echo ""
  echo "EC2 key (.pem) is required to SSH. Key not found or not set."
  exit 1
fi

chmod 600 "$KEY" 2>/dev/null || true
echo "==> Deploying to ec2-user@${EC2_HOST}..."
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ec2-user@${EC2_HOST}" << 'REMOTE'
  if [ ! -d ~/paystub-service ]; then
    echo "Repo not found. First-time setup: clone and bootstrap."
    git clone https://github.com/netayamin/paystub-service.git && cd paystub-service && bash scripts/ec2-bootstrap.sh
    exit 0
  fi
  cd ~/paystub-service
  git pull origin main
  GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
  # Use plain docker build to avoid "compose build requires buildx 0.17.0 or later" on older EC2
  sudo docker build --build-arg GIT_SHA="$GIT_SHA" --no-cache -t paystub-service-backend ./backend
  if command -v docker-compose >/dev/null 2>&1; then
    DC="sudo docker-compose -f docker-compose.prod.yml"
  else
    DC="sudo docker compose -f docker-compose.prod.yml"
  fi
  $DC run --rm backend alembic upgrade head || true
  $DC up -d --force-recreate backend
  $DC ps
  echo "Deploy done. API: http://$(curl -s -m 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo EC2_IP):8000"
REMOTE

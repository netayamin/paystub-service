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
  # Build backend with --no-cache so code changes (e.g. discovery time filtering) are not skipped by layer cache
  if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_BUILDKIT=0 sudo docker-compose -f docker-compose.prod.yml build --no-cache backend
    DOCKER_BUILDKIT=0 sudo docker-compose -f docker-compose.prod.yml up -d
    sudo docker-compose -f docker-compose.prod.yml ps
  else
    DOCKER_BUILDKIT=0 sudo docker compose -f docker-compose.prod.yml build --no-cache backend
    DOCKER_BUILDKIT=0 sudo docker compose -f docker-compose.prod.yml up -d
    sudo docker compose -f docker-compose.prod.yml ps
  fi
  echo "Deploy done. API: http://$(curl -s -m 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo EC2_IP):8000"
REMOTE

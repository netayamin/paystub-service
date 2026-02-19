#!/bin/bash
# Run this ON the EC2 instance (after SSH). Installs Docker, builds and runs backend only.
# Postgres is NOT run in Docker — use AWS RDS or another external DB. Set DATABASE_URL in backend/.env.
# Usage: git clone https://github.com/netayamin/paystub-service.git && cd paystub-service && bash scripts/ec2-bootstrap.sh
set -e

echo "==> Detecting OS..."
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "Cannot detect OS. Use Amazon Linux 2023 or Ubuntu 22.04."
  exit 1
fi

echo "==> Installing Docker..."
if [ "$OS" = "amzn" ]; then
  sudo dnf update -y
  sudo dnf install -y docker
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker "$USER" || true
  if command -v docker compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
  else
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    DOCKER_COMPOSE="docker-compose"
  fi
else
  # Ubuntu
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  DOCKER_COMPOSE="docker compose"
fi

# Run docker without sudo for this session (if we're in a new group we might need re-login; try anyway)
sudo docker info >/dev/null 2>&1 && export DOCKER_HOST= || true

echo "==> Preparing app..."
if [ ! -f docker-compose.prod.yml ]; then
  echo "Run this script from the repo root (paystub-service)."
  echo "Example: git clone https://github.com/netayamin/paystub-service.git && cd paystub-service && bash scripts/ec2-bootstrap.sh"
  exit 1
fi

if [ ! -f backend/.env ]; then
  cp backend/.env.example backend/.env
  echo "Created backend/.env from example."
fi

if ! grep -q '^DATABASE_URL=.\+@.\+:' backend/.env 2>/dev/null; then
  echo "WARNING: DATABASE_URL in backend/.env should point to your RDS (or external Postgres)."
  echo "  Example: DATABASE_URL=postgresql://paystub:pass@your-db.region.rds.amazonaws.com:5432/paystub"
  echo "  Edit backend/.env and set DATABASE_URL, OPENAI_API_KEY, RESY_API_KEY, RESY_AUTH_TOKEN, then re-run:"
  echo "    sudo $DOCKER_COMPOSE -f docker-compose.prod.yml up -d"
  echo ""
fi

echo "==> Building and starting backend (no Postgres in Docker — use RDS)..."
sudo $DOCKER_COMPOSE -f docker-compose.prod.yml up -d --build

echo "==> Running DB migrations (once)..."
sudo $DOCKER_COMPOSE -f docker-compose.prod.yml run --rm backend alembic upgrade head || true

echo ""
echo "==> Done. Backend container is starting."
echo ""
PUBLIC_IP=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<EC2_PUBLIC_IP>")
echo "  API URL:  http://${PUBLIC_IP}:8000"
echo "  Health:   http://${PUBLIC_IP}:8000/health"
echo "  Docs:     http://${PUBLIC_IP}:8000/docs"
echo ""
echo "If you have not set secrets yet:"
echo "  1. Edit: nano backend/.env   (DATABASE_URL=RDS URL, OPENAI_API_KEY, RESY_API_KEY, RESY_AUTH_TOKEN)"
echo "  2. Restart: sudo $DOCKER_COMPOSE -f docker-compose.prod.yml restart backend"
echo ""
echo "Logs: sudo $DOCKER_COMPOSE -f docker-compose.prod.yml logs -f backend"

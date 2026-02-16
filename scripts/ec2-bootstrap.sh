#!/bin/bash
# Run this ON the EC2 instance (after SSH). Installs Docker, builds and runs backend + Postgres.
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
  if ! command -v docker compose >/dev/null 2>&1; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  fi
  DOCKER_COMPOSE="docker compose"
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
  echo "Created backend/.env from example. You must add OPENAI_API_KEY, RESY_API_KEY, RESY_AUTH_TOKEN."
fi

echo "==> Building and starting backend + Postgres..."
sudo $DOCKER_COMPOSE -f docker-compose.prod.yml up -d --build

echo ""
echo "==> Done. Containers are starting."
echo ""
PUBLIC_IP=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<EC2_PUBLIC_IP>")
echo "  API URL:  http://${PUBLIC_IP}:8000"
echo "  Health:   http://${PUBLIC_IP}:8000/health"
echo "  Docs:     http://${PUBLIC_IP}:8000/docs"
echo ""
echo "If you have not set secrets yet:"
echo "  1. Edit: nano backend/.env   (add OPENAI_API_KEY, RESY_API_KEY, RESY_AUTH_TOKEN)"
echo "  2. Restart: sudo $DOCKER_COMPOSE -f docker-compose.prod.yml restart backend"
echo ""
echo "Logs: sudo $DOCKER_COMPOSE -f docker-compose.prod.yml logs -f backend"

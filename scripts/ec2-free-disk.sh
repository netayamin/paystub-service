#!/bin/bash
# Run this ON the EC2 instance to free disk before a deploy (when you see "no space left on device").
# Usage on EC2: cd ~/paystub-service && bash scripts/ec2-free-disk.sh
# Then from your Mac run: EC2_KEY=your.pem ./scripts/deploy-to-ec2.sh
set -e
echo "=== Disk before ==="
df -h /
echo ""
echo "Stopping backend container..."
sudo docker compose -f docker-compose.prod.yml stop backend 2>/dev/null || sudo docker-compose -f docker-compose.prod.yml stop backend 2>/dev/null || true
echo "Pruning Docker (images, containers, networks, build cache)..."
sudo docker system prune -af
sudo docker builder prune -af
echo ""
echo "=== Disk after ==="
df -h /
echo ""
echo "Done. Run your deploy from Mac (or restart backend on EC2: sudo docker compose -f docker-compose.prod.yml up -d)."

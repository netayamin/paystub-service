#!/usr/bin/env bash
# Run from your Mac to check EC2 → RDS connectivity and restart backend.
# Usage: EC2_KEY=~/.ssh/your.pem EC2_IP=3.19.238.117 ./scripts/check-ec2-rds.sh

set -e
KEY="${EC2_KEY:-$HOME/Downloads/dropfeed.pem}"
IP="${EC2_IP:-3.19.238.117}"

if [ ! -f "$KEY" ]; then
  echo "Set EC2_KEY to your .pem path. Example: EC2_KEY=~/Downloads/dropfeed.pem $0"
  exit 1
fi

echo "=== 1. Testing RDS from EC2 (port 5432) ==="
ssh -i "$KEY" -o ConnectTimeout=10 "ec2-user@${IP}" \
  'sudo docker run --rm -e PGPASSWORD="Netayamin89*" postgres:15-alpine psql -h database-1.ctagye24ambt.us-east-2.rds.amazonaws.com -p 5432 -U postgres -d postgres -t -c "SELECT 1"' 2>&1 && echo "RDS: OK" || echo "RDS: FAILED (add this EC2 security group to RDS inbound 5432)"

echo ""
echo "=== 2. Restarting backend container ==="
ssh -i "$KEY" "ec2-user@${IP}" "sudo docker restart paystub-backend"

echo ""
echo "=== 3. Waiting 8s then checking /health ==="
sleep 8
ssh -i "$KEY" "ec2-user@${IP}" "curl -s -m 5 http://localhost:8000/health" && echo "" && echo "Backend: OK" || echo "Backend: not responding yet (check: sudo docker logs paystub-backend)"

echo ""
echo "Try in browser: http://${IP}:8000/health"

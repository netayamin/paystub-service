#!/usr/bin/env bash
# Diagnose "same results / no live updates" on EC2.
# Run ON the EC2 instance (after SSH):
#   cd ~/paystub-service && bash scripts/ec2-diagnose-discovery.sh
# Or from your Mac (replace with your EC2 IP):
#   BASE_URL=http://18.118.55.231:8000 bash scripts/ec2-diagnose-discovery.sh
set -e
BASE_URL="${BASE_URL:-http://localhost:8000}"

echo "=============================================="
echo "  Discovery / live-updates diagnostic"
echo "  BASE_URL=$BASE_URL"
echo "=============================================="
echo ""

echo "1. Health"
curl -s -o /dev/null -w "   HTTP %{http_code}\n" "$BASE_URL/health" || true
echo ""

echo "2. Discovery health (job heartbeat, last_scan_at, bucket status)"
curl -s "$BASE_URL/discovery/health" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    err = d.get('error')
    if err:
        print('   ERROR:', err)
    else:
        fc = d.get('fast_checks') or {}
        hb = d.get('job_heartbeat') or {}
        disc = d.get('discovery') or {}
        print('   last_scan_at:     ', disc.get('last_scan_at') or 'none')
        print('   feed_updating:    ', fc.get('feed_updating'))
        print('   job_alive:        ', fc.get('job_alive'))
        print('   in_flight_count:  ', hb.get('in_flight_count'))
        print('   stale_bucket_count:', d.get('stale_bucket_count', 0))
        if d.get('critical'):
            print('   CRITICAL:         ', (d.get('message') or '')[:80])
except Exception as e:
    print('   Parse error:', e)
" 2>/dev/null || echo "   (curl or parse failed)"
echo ""

echo "3. Feed live (snapshot path unless debug) – ranked_board / just_opened counts"
curl -s "$BASE_URL/feed/live" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    rb = d.get('ranked_board') or []
    jo = d.get('just_opened') or []
    total = sum(len(day.get('venues') or []) for day in jo)
    print('   ranked_board count:', len(rb))
    print('   just_opened venues (sum):', total)
    print('   last_scan_at:      ', d.get('last_scan_at'))
except Exception as e:
    print('   Parse error:', e)
" 2>/dev/null || echo "   (parse failed)"
echo ""

echo "4. Feed live with debug=1 (bypass snapshot, hit DB) – same?"
curl -s "$BASE_URL/feed/live?debug=1" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    rb = d.get('ranked_board') or []
    jo = d.get('just_opened') or []
    total = sum(len(day.get('venues') or []) for day in jo)
    print('   ranked_board count:', len(rb))
    print('   just_opened venues (sum):', total)
    print('   last_scan_at:      ', d.get('last_scan_at'))
except Exception as e:
    print('   Parse error:', e)
" 2>/dev/null || echo "   (parse failed)"
echo ""

echo "=============================================="
echo "  What to do next (run these ON EC2)"
echo "=============================================="
echo ""
echo "  # Backend logs (discovery job, snapshot rebuild, Resy errors):"
echo "  docker compose -f docker-compose.prod.yml logs --tail=150 backend"
echo "  # or: docker-compose -f docker-compose.prod.yml logs --tail=150 backend"
echo ""
echo "  # If last_scan_at is old or missing: discovery job may not be running."
echo "  # If snapshot and debug=1 give same counts but both are old:"
echo "  #   - Resy may be returning no new drops (same availability)."
echo "  #   - Or RESY_API_KEY / RESY_AUTH_TOKEN missing or invalid in backend/.env."
echo ""
echo "  # Ensure .env on EC2 has: DATABASE_URL, RESY_API_KEY, RESY_AUTH_TOKEN"
echo "  cat backend/.env | grep -E '^DATABASE_URL|^RESY_' | sed 's/=.*/=***/'"
echo ""

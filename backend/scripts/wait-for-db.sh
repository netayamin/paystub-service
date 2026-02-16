#!/bin/sh
# Wait for Postgres to be ready (used in prod compose).
set -e
until python -c "
import os, sys
import psycopg2
try:
    conn = psycopg2.connect(os.environ.get('DATABASE_URL', 'postgresql://paystub:paystub@db:5432/paystub'))
    conn.close()
except Exception as e:
    sys.exit(1)
" 2>/dev/null; do
  echo "Waiting for database..."
  sleep 2
done
echo "Database is ready."

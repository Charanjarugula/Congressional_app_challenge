#!/usr/bin/env bash
# Applies every migration, the seed and the smoke test to a plain Postgres 16, standing in the
# Supabase-provided pieces (auth, storage, vault, cron, net, and a PostGIS stand-in) with shim.sql.
# Connection comes from the usual PG* variables. The target database is dropped and recreated.
#
#   PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres supabase/tests/local/run.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DB=${PGDATABASE:-courtly_test}
export PGDATABASE=postgres
psql -v ON_ERROR_STOP=1 -qc "drop database if exists $DB;" && psql -v ON_ERROR_STOP=1 -qc "create database $DB;"
export PGDATABASE=$DB
psql -v ON_ERROR_STOP=1 -q -f "$HERE/shim.sql" || { echo "shim failed"; exit 1; }

prep() {
  sed -E \
    -e '/create extension if not exists (postgis|pg_cron|pg_net)/d' \
    -e 's/extensions\.geography\(point, 4326\)/extensions.geography/g' \
    -e 's/::extensions\.geography//g' \
    -e 's/::extensions\.geometry//g' \
    -e '/using gist/d' \
    "$1"
}
for f in "$ROOT"/migrations/*.sql; do
  echo "migrate $(basename "$f")"
  prep "$f" | psql -v ON_ERROR_STOP=1 -q -o /dev/null || { echo "FAILED: $(basename "$f")"; exit 1; }
done
for f in "$ROOT"/seed/*.sql; do
  echo "seed    $(basename "$f")"
  prep "$f" | psql -v ON_ERROR_STOP=1 -q -o /dev/null || { echo "FAILED: $(basename "$f")"; exit 1; }
done
echo "smoke   tests/smoke.sql"
out=$(prep "$ROOT/tests/smoke.sql" | psql -v ON_ERROR_STOP=1 -q 2>&1)
if echo "$out" | grep -q "SMOKE_OK"; then echo "smoke passed"; else echo "$out" | head -40; echo "smoke FAILED"; exit 1; fi

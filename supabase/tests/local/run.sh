#!/usr/bin/env bash
# Applies every migration, the seed, the smoke test, the reviewer account and the demo world to a
# plain Postgres 16, standing in the Supabase-provided pieces (auth, storage, vault, cron, net, and
# a PostGIS stand-in) with shim.sql.
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
# Function calls are tracked so the run can tell which functions the test never reached.
out=$({ echo "set track_functions = 'all';"; prep "$ROOT/tests/smoke.sql"; } | psql -v ON_ERROR_STOP=1 -q 2>&1)
if echo "$out" | grep -q "SMOKE_OK"; then echo "smoke passed"; else echo "$out" | head -40; echo "smoke FAILED"; exit 1; fi

# Every function in the schema has to run at least once: a branch no test reaches is where the next
# add_court-style bug hides (that one failed only when inserting a new court).
missed=$(psql -At -c "select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  left join pg_stat_user_functions s on s.funcid = p.oid
  where n.nspname in ('public', 'private') and s.calls is null order by 1")
if [ -n "$missed" ]; then
  echo "functions the smoke test never called:"; echo "$missed" | sed 's/^/  /'; echo "coverage FAILED"; exit 1
fi
echo "coverage every function ran"

# The App Review account and the demo world, built twice (the second run takes the first down) and
# then removed, so those scripts are proven against the current schema as well. The settings stand
# in for the passwords the deploy step passes.
apply() { { echo "select set_config('$1', '$2', false);"; prep "$3"; } | psql -v ON_ERROR_STOP=1 -q -o /dev/null; }
echo "reviewer reviewer/account.sql"
apply courtly.reviewer_password 12345678 "$ROOT/reviewer/account.sql" || { echo "FAILED: reviewer/account.sql"; exit 1; }
for round in 1 2; do
  for f in reset players world reviewer; do
    apply courtly.demo_password demo-local "$ROOT/demo/$f.sql" || { echo "FAILED: demo/$f.sql (round $round)"; exit 1; }
  done
  prep "$ROOT/tests/demo.sql" | psql -v ON_ERROR_STOP=1 -q -o /dev/null || { echo "FAILED: tests/demo.sql (round $round)"; exit 1; }
done
echo "demo    built twice, checked from the reviewer's side"
for f in demo/reset demo/remove reviewer/remove; do
  prep "$ROOT/$f.sql" | psql -v ON_ERROR_STOP=1 -q -o /dev/null || { echo "FAILED: $f.sql"; exit 1; }
done
left=$(psql -At -c "select (select count(*) from public.profiles) + (select count(*) from public.hits) + (select count(*) from public.chats) + (select count(*) from public.messages) + (select count(*) from public.notifications) + (select count(*) from auth.users)")
if [ "$left" != "0" ]; then echo "demo removal left $left rows behind"; exit 1; fi
echo "demo    removed without a trace"

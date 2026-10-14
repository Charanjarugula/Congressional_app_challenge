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
# Migrations are recorded the way the deploy records them, hash included, so the status report has its table.
migrate_all() {
  psql -v ON_ERROR_STOP=1 -qc "create schema if not exists private; create table private.app_migrations (name text primary key, applied_at timestamptz not null default now(), sha256 text);"
  for f in "$ROOT"/migrations/*.sql; do
    echo "migrate $(basename "$f")"
    { prep "$f"; echo "insert into private.app_migrations (name, sha256) values ('$(basename "$f")', '$(sha256sum "$f" | cut -c1-64)');"; } \
      | psql -v ON_ERROR_STOP=1 -q -o /dev/null || { echo "FAILED: $(basename "$f")"; exit 1; }
  done
}
migrate_all
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
run_sql() { prep "$ROOT/$1.sql" | psql -v ON_ERROR_STOP=1 -q -o /dev/null || { echo "FAILED: $1.sql"; exit 1; }; }
build_demo() {
  for f in "$@"; do apply courtly.demo_password demo-local "$ROOT/demo/$f.sql" || { echo "FAILED: demo/$f.sql"; exit 1; }; done
  run_sql tests/demo
}
echo "reviewer reviewer/account.sql"
apply courtly.reviewer_password 12345678 "$ROOT/reviewer/account.sql" || { echo "FAILED: reviewer/account.sql"; exit 1; }
build_demo reset players world reviewer
build_demo reset players world reviewer
echo "demo    built twice, checked from the reviewer's side"

# A demo player holding a seat in someone else's hit: the reset gives the seat back, under a lock, and
# only once. Sam, who is not part of the demo, hosts; Ana joins; the reset runs; Sam's hit is open again.
psql -v ON_ERROR_STOP=1 -q <<'SQL'
do $$
declare v_sam uuid := '00000000-0000-4000-8000-00000000005a'; v_ana uuid; v_court uuid; v_hit jsonb; v_req jsonb;
begin
  insert into public.profiles (id, first_name, last_name, birthday, level, formats, zip, area_label, home_point, onboarding_completed_at)
  values (v_sam, 'Sam', 'Host', '1991-01-01', 'intermediate', '{casual}', '33414', 'Wellington, FL', extensions.st_setsrid(extensions.st_makepoint(-80.2414, 26.6618), 4326), now());
  select id into v_ana from auth.users where email = 'demo.ana@courtly.app';
  select id into v_court from public.courts where name = 'Wellington Tennis Center';
  perform set_config('request.jwt.claims', json_build_object('sub', v_sam, 'role', 'authenticated')::text, true);
  v_hit := public.create_hit(v_court, now() + interval '4 days', 60, 'casual', 1, 'anyone');
  perform set_config('request.jwt.claims', json_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  v_req := public.request_to_join((v_hit->>'id')::uuid);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sam, 'role', 'authenticated')::text, true);
  perform public.respond_to_request((v_req->'viewer'->'request'->>'id')::uuid, true);
end $$;
SQL
run_sql demo/reset
seat=$(psql -At -c "select status || '/' || spots_open || '/' || (select count(*) from public.hit_players hp where hp.hit_id = h.id and hp.role = 'player' and hp.left_at is null) from public.hits h where host_id = '00000000-0000-4000-8000-00000000005a'")
[ "$seat" = "open/1/0" ] || { echo "reset left Sam's hit at $seat (wanted open/1/0)"; exit 1; }
psql -v ON_ERROR_STOP=1 -qc "delete from public.chats where hit_id in (select id from public.hits where host_id = '00000000-0000-4000-8000-00000000005a'); delete from public.hits where host_id = '00000000-0000-4000-8000-00000000005a'; delete from public.profiles where id = '00000000-0000-4000-8000-00000000005a';"
echo "demo    reset gives back a seat held in someone else's hit"

# Removing the review account on its own, with the world still up, gives back the seat it held in Ana's
# one-seat hit and leaves nothing of the account, not even its line in the group chat.
build_demo players world reviewer
run_sql reviewer/remove
seat=$(psql -At -c "select h.status || '/' || h.spots_open from public.hits h join public.profiles p on p.id = h.host_id where p.first_name = 'Ana' and h.status <> 'cancelled' order by h.starts_at limit 1")
[ "$seat" = "open/1" ] || { echo "reviewer removal left Ana's hit at $seat (wanted open/1)"; exit 1; }
left=$(psql -At -c "select (select count(*) from auth.users where email = 'reviewer@courtly.app') + (select count(*) from public.profiles where first_name = 'App') + (select count(*) from public.messages where body like 'Thanks! Saturday mornings%')")
[ "$left" = "0" ] || { echo "reviewer removal left $left rows of the account (sign-in, profile or a group message)"; exit 1; }
echo "reviewer removed on its own; the seat it held is open again"

run_sql demo/reset
run_sql demo/remove
left=$(psql -At -c "select (select count(*) from public.profiles) + (select count(*) from public.hits) + (select count(*) from public.chats) + (select count(*) from public.messages) + (select count(*) from public.notifications) + (select count(*) from auth.users)")
if [ "$left" != "0" ]; then echo "demo removal left $left rows behind"; exit 1; fi
echo "demo    removed without a trace"

# The status report has to run against the schema as well; its lines are shown for a look.
report=$(prep "$ROOT/tests/status.sql" | psql -v ON_ERROR_STOP=1 -qAt -F ' = ') || { echo "FAILED: tests/status.sql"; exit 1; }
echo "$report" | sed 's/^/status  /'

# The dev-only reset has to take out everything the migrations made, asking the catalogs rather than a
# list, and the migrations have to run again from what it leaves. Accounts go with it; the bucket stays.
echo "reset   reset.sql"
dropped=$({ echo "set client_min_messages = warning;"; cat "$ROOT/reset.sql"; } | psql -v ON_ERROR_STOP=1 -qAt -F '|') || { echo "FAILED: reset.sql"; exit 1; }
echo "$dropped" | cut -d'|' -f1 | sort | uniq -c | awk '{printf "reset   %s %s%s\n", $1, $2, ($3 ? " " $3 : "")}'
left=$(psql -At -c "select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'S'))
  + (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public')
  + (select count(*) from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typtype in ('e', 'd'))
  + (select count(*) from pg_namespace where nspname = 'private')
  + (select count(*) from cron.job) + (select count(*) from pg_policies where schemaname = 'storage')
  + (select count(*) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal)
  + (select count(*) from auth.users) + (select count(*) from vault.secrets where name like 'apple-refresh-%')")
[ "$left" = "0" ] || { echo "reset left $left objects or rows behind"; exit 1; }
migrate_all
recorded=$(psql -At -c "select count(*)::text || ' recorded, ' || count(sha256)::text || ' with hash' from private.app_migrations")
echo "reset   left nothing of the migrations behind; every file applied again from empty: $recorded"

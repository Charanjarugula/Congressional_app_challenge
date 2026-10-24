#!/usr/bin/env python3
"""Create the shared recording fixture once, only on courtly-dev. No production target."""
import json
import pathlib
import secrets
import subprocess
import tempfile
import os

ROOT = pathlib.Path(__file__).resolve().parents[2]
REF = 'letuvtazmtjkvivattfy'
private = ROOT / '.recording'
private.mkdir(mode=0o700, exist_ok=True)
credentials = private / 'shared-credentials.json'
if not credentials.exists():
    codes = {name: str(secrets.randbelow(90_000_000) + 10_000_000) for name in ('ana', 'luis')}
    fd = os.open(credentials, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(codes, f)
codes = json.loads(credentials.read_text())
assert all(len(v) == 8 and v.isdigit() for v in codes.values())
query = """begin;
do $$ begin
if exists(select 1 from auth.users where email like 'recording.%@courtly.app') then
  raise exception 'Recording accounts already exist. Refusing to overwrite any account.';
end if;
end $$;
create temp table reviewer_before as
select md5(row_to_json(u)::text) digest from auth.users u where email='reviewer@courtly.app';
"""
for name, code in codes.items():
    query += f"select set_config('courtly.recording_{name}', '{code}', true);\n"
for filename in ('players.sql', 'world.sql', 'activity.sql'):
    query += (ROOT / 'scripts/shared-recording' / filename).read_text() + '\n'
query += """
do $$ begin
if exists((select digest from reviewer_before except select md5(row_to_json(u)::text) from auth.users u where email='reviewer@courtly.app')
union all (select md5(row_to_json(u)::text) from auth.users u where email='reviewer@courtly.app' except select digest from reviewer_before)) then
raise exception 'Reviewer account changed'; end if;
end $$;
commit;
select count(*) as recording_players from auth.users where email like 'recording.%@courtly.app';
"""
with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', dir=private) as f:
    f.write(query)
    f.flush()
    result = subprocess.run(['supabase', 'db', 'query', '--linked', '--project-ref', REF,
                             '--file', f.name, '-o', 'json'], capture_output=True, text=True, cwd=ROOT)
    if result.returncode:
        # Avoid logging SQL/credentials if a remote error echoes query text.
        error = result.stderr
        for code in codes.values():
            error = error.replace(code, '[redacted]')
        raise SystemExit(error)
    print(result.stdout)
print('Shared recording fixture created. Credentials stay in .recording/shared-credentials.json.')

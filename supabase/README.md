# Courtly backend

Everything the app calls lives in Postgres: `migrations/` (schema, row-level security and every database function, applied in order and never edited once deployed), `seed/` (courts and the blocked-words list), `functions/` (Deno Edge Functions: `send-push`, `delete-account`, `apple-token-exchange`, `report-email`), `reviewer/` and `demo/` (the App Review account and its demo world), `tests/` (the smoke test, the reviewer-side check and a local Postgres harness), and `reset.sql` (dev-only: back to before the first migration).

- Local check, from the repository root, against a Postgres 16 you can scratch (it drops and recreates `courtly_test`):
  `PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres supabase/tests/local/run.sh`
- Deploy: `node scripts/supabase-deploy.mjs check migrate seed settings auth secrets functions test status` with `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` set; the Backend deploy workflow runs the same steps. Secrets it reads and how dev and prod are deployed are in the [root README](../README.md#deploying-the-backend).
- A new function the app should call needs `grant execute … to authenticated` in its migration and a check in `tests/smoke.sql`; the harness fails if any function goes unexecuted.

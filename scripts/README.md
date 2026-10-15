# Scripts

- `supabase-deploy.mjs` — deploys the backend to a Supabase project through the management API: migrations with a hash ledger, seeds, settings, auth config, secrets, Edge Functions, the smoke test and a status report. Needs `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF`; the header comment lists every step. Run from the repository root.
- `testflight.sh` — archives the Release app and uploads it to TestFlight with an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, optional `ASC_KEY_PATH`). Run from the repository root on a Mac; `--archive-only` stops before anything leaves the machine.

Both are documented in more detail in the [root README](../README.md).

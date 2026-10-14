# Review guide for Courtly

Courtly helps recreational tennis players in Palm Beach County find a hit: one time, one public court, one format, open spots. The app is SwiftUI on iOS 17+; the backend is Supabase (Postgres with PostGIS, row-level security, security-definer functions, Deno Edge Functions, pg_cron, pg_net); the policy site is static HTML on Vercel.

## What matters most

1. **Security of the API surface.** Only the functions granted in `supabase/migrations/0009_function_grants.sql` are callable. A helper that takes an arbitrary user, hit or chat id and ends up callable over PostgREST is a data leak.
2. **Privacy promises.** Other players see first name, last initial, level, area label and availability only. No precise coordinates, no phone numbers, no birthdays, no email. The site pages must describe the real behavior.
3. **App and backend agreeing.** Every RPC the app calls has a typed wrapper in `ios/Courtly/Services/API.swift`; models in `ios/Courtly/Models` mirror the `*_json` builders in SQL. Renamed parameters, new nullable fields or new error codes must be updated on both sides.
4. **State that outlives a screen.** Stores (`HitsStore`, `InboxStore`, `AppSession`), the Realtime hub, caches and the badge are shared; sign-out must reset all of them, and overlapping refreshes must not overwrite newer state with older responses.

## Conventions

- Pull request descriptions follow `.github/pull_request_template.md`: Summary, Setup, What Changed, Test Plan.
- Nothing is pushed to `main` directly; CI builds the simulator app for `ios/**` changes and runs the migrations plus `supabase/tests/smoke.sql` on a throwaway Postgres for `supabase/**` changes.
- Backend errors are short snake_case codes mapped to copy in `BackendMessages.swift`.
- Time zone for server-side labels is America/New_York; the app formats in the device zone.

## Things not worth a comment

- SwiftUI padding, spacing and color choices that use the `CourtlyFont`, `CourtlyColor` and `CourtlyMetrics` tokens.
- Xcode project file churn.
- Wording in sample data or placeholder text.

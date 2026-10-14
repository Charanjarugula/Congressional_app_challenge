# Courtly

iOS app that helps recreational tennis players in Palm Beach County get on court. The unit is a **hit**: one time, one public court, one format, one or more open spots. Post an open hit or invite someone; when accepted it is confirmed and a chat opens. Four tabs: Play, My Hits, People, You.

## Stack

SwiftUI (iOS 17+) talking to Supabase (Postgres with PostGIS, Auth, Storage, Edge Functions) over plain `URLSession`. Apple Push Notifications, EventKit, MapKit, Contacts. The policy site is static HTML on Vercel.

## Repository

| Path | What |
|---|---|
| `ios/Courtly.xcodeproj` | Open this in Xcode 16 or newer. |
| `ios/Courtly/App` | App entry, root view, session state, notification delegate. |
| `ios/Courtly/Config` | Supabase URLs and keys per environment, policy links. |
| `ios/Courtly/DesignSystem` | Color and type tokens, shared components (cards, pills, buttons, avatars). |
| `ios/Courtly/Features` | One folder per screen group: Onboarding, Main (tab shell, stores), Play, Hits, Chat, People, You. |
| `ios/Courtly/Models` | Plain data types matching the backend's JSON shapes. |
| `ios/Courtly/Services` | Supabase client, typed `API` wrappers, device services (location, calendar, contacts, notifications), snapshot cache. |
| `supabase/migrations` | The schema, row-level security, and every database function the app calls, in order. |
| `supabase/functions` | Edge Functions: `send-push`, `delete-account`, `apple-token-exchange`. |
| `supabase/seed` | Public courts and the blocked-words list. |
| `supabase/demo` | The demo world: four demo players and everything the App Review account sees, rebuilt by the deploy's `demo` step. |
| `supabase/reviewer` | The App Review account: create or update, and remove. |
| `supabase/tests` | The smoke test that runs after each deploy, the reviewer-side check of the demo world, and a local Postgres harness. |
| `scripts/supabase-deploy.mjs` | Deploys migrations, seeds, settings, secrets and functions through the Supabase management API. |
| `site/` | Privacy policy, terms and support pages. Vercel root directory is `site`. |

## Running the app

```sh
open ios/Courtly.xcodeproj
```

Select an iPhone simulator and press Run. Debug builds talk to the `courtly-dev` Supabase project, Release builds to `courtly-prod` (see `ios/Courtly/Config/AppConfig.swift`). The project uses Xcode's synchronized folders, so new files added under `ios/Courtly` are picked up automatically.

To run on a device, choose your team under Signing & Capabilities. The bundle id is `com.courtly.ios`.

## How the app talks to the backend

Every read and write is one database function (`get_play_feed`, `create_hit`, `send_message`, ...) called through `API.swift`. Row-level security guards direct table access; the functions run as security definer and check the caller themselves. Only those entry points are callable over the API: helpers such as `hit_json` or `chat_json` have no grant, so a new function the app should call needs `grant execute ... to authenticated` in its migration (see `0009_function_grants.sql`). The row policies take the caller from the session through the `viewer_*` wrappers (`0011_review_fixes.sql`); the two-player helpers such as `is_blocked_either` and `is_chat_member` are not callable by the app role, and neither is the `chats` table, which the app only ever reads through `chat_json`. Errors raised as short codes (`hit_full`, `already_requested`) are turned into plain sentences in `BackendMessages.swift`.

Play, My Hits, the People list and the profile keep the last response on disk so they paint before the network answers. Open chats, the People list and the hit tabs listen over Supabase Realtime (`RealtimeHub.swift`, one connection for the app) for rows they are allowed to see and refresh at once; a slow poll stays on as the fallback.

## Deploying the backend

The **Backend deploy** workflow (Actions tab) takes a target (`dev` or `prod`) and the steps to run. Repository secrets it reads: `SUPABASE_ACCESS_TOKEN` (required), `WEBHOOK_SECRET` and `REVIEWER_PASSWORD` (keep the push webhook and the App Review account in agreement with what is deployed), `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_PRIVATE_KEY` (push and Sign in with Apple), `GOOGLE_CLIENT_ID`, `SMTP_USER` and `SMTP_PASS` (email codes through Gmail). `scripts/supabase-deploy.mjs` lists which step uses which. Optional steps: `reviewer` and `reviewer-remove` for the App Review account, `demo` and `demo-remove` for the world it sees (friends, chats, requests, hits); run `demo` on prod before submitting to App Review and `demo-remove` before launch. `DEMO_PASSWORD`, when set, is the demo players' sign-in password. `status` prints one line per fact about the deployed project (migrations recorded, cron jobs, grants, counts) without changing anything.

### Auth configuration

Email sign-in sends a six-digit code, so the Supabase project needs: OTP length 6 and expiry 600 s; the Magic Link and Confirm signup templates containing `{{ .Token }}`; and an SMTP server (the built-in mailer allows two emails an hour). Sign in with Apple needs the Apple provider enabled with the bundle id as client id; Google needs the iOS client id. The deploy's `auth` step sets all of this from the secrets above when the access token has the auth-config scope, and prints the values to set by hand in Authentication → Email and Providers when it doesn't.

Pull requests that touch `supabase/` run the migrations and the smoke test against a throwaway Postgres in CI; the run fails if any function in the schema went unexecuted, so a new function needs a check in `supabase/tests/smoke.sql`. Migrations are append-only once a project has recorded them in `private.app_migrations`: a change to a function is a new numbered file that re-creates it (`0010_…`, `0011_…`), never an edit to a file already applied, so `migrate` can tell what is new.

## Working in this repo

- Branch from `main` and open a pull request. Nothing is pushed to `main` directly.
- Keep pull request descriptions short: Summary, Setup, What Changed, Test Plan.
- CI builds the app for the iOS Simulator on every push that touches `ios/`.

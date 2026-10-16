<p align="center">
  <img src="ios/Courtly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Courtly app icon">
</p>

# Courtly

**Find a tennis partner for this week, at a public court near you.** Courtly is an iOS app that helps tennis players of all levels find hitting partners based of location and time built.

In development; not yet in the App Store. The privacy policy, terms and support contact live at [courtly-sage.vercel.app](https://courtly-sage.vercel.app).

## The problem

Palm Beach County has many free public courts and plenty of people who would play more if they had someone to play with. Finding that someone for Saturday morning usually means a group text, a few maybes, and a court that stays empty. Players new to the area, or new to the game, often have nobody to ask at all.

## What Courtly does

You post a **hit**: one time, one public court, the kind of tennis you want (casual rally, singles, doubles or drills) and how many spots are open. Friends and nearby players see it and ask to join; when you accept, the hit is confirmed and a chat opens for it. You can invite a friend or a whole group straight to a hit, mark the hours you are usually free so the right hits reach you, and after you play, say who showed up. The app is where hits get found and organized; the website is a landing page with the policies and the support address.

## What works today

- **Post a hit** with a time, court, format and open spots; edit or cancel it later (`PlanHitView`, `HitDetailView`; `create_hit`, `update_hit`, `cancel_hit`).
- **Ask to join**; the host accepts or declines; a confirmed hit gets its own chat (`JoinRequestView`; `request_to_join`, `respond_to_request`).
- **Invite a friend or a group** to a hit; the first tap takes the spot (`InviteSheet`, `HitInviteCard`; `send_hit_invite`, `claim_invite`).
- **Leave a hit**; a host who leaves hands it to the first player who joined (`leave_hit`).
- **Chats**: one per hit, direct messages with friends, and groups you create (`ChatThreadView`, `NewGroupView`; `send_message`, `create_group`).
- **Friends**: send and accept requests, see mutual friends, find people from your contacts without uploading them (only hashes are compared) (`AddFriendsView`, `FriendRequestsView`; `match_contacts`, `get_friend_suggestions`).
- **Nearby**: a new player sees how many players, open hits and courts are around them (`SuggestedPlayersRow`; `get_area_pulse`).
- **Availability**: a weekly grid of free and busy blocks, with Apple Calendar events marked busy if you connect it; hits in busy blocks stay out of your feed (`AvailabilitySheet`, `CalendarService`).
- **Courts**: 25 public courts in the county to start with; add another from a Maps search (`CourtPickerView`; `add_court`).
- **Day-after check**: say whether each player showed up; repeated no-shows are counted (`MyHitsView`; `submit_attendance`).
- **Safety**: block players, report them, and every report reaches the support inbox by email (`ReportView`, `BlockedPlayersView`; `report_user`, the `report-email` function).
- **Live updates**: open chats and the hit lists refresh when another phone changes them (`RealtimeHub`).
- **Sign in** with Apple, Google or an email code; **delete your account** from the app (`AuthService`; the `delete-account` function).
- **Reminders and pushes** the day before and the hour before a confirmed hit, and for requests, invites and messages (`send-push`, the scheduler in `0008_scheduler.sql`).

Not yet: Android. Phone numbers are never collected.

## How it works

Maya posts a casual hit for Thursday at 6:30 PM at Wellington Tennis Center with one open spot. Luis, two miles away, sees it on Play and asks to join. Maya accepts; the hit turns confirmed and a chat opens with the two of them. Both get a reminder the day before and an hour before. The morning after, My Hits asks each of them whether the other showed up.

## Tech stack

| Area | Technology | What it does here |
|---|---|---|
| App | Swift, SwiftUI, iOS 17+ | The four tabs, onboarding, the sheets; talks to the backend over plain `URLSession`. |
| Data and sign-in | Supabase: Postgres with PostGIS, Auth, Storage, Realtime | Profiles, courts, hits, chats; Apple, Google and email sign-in; avatar photos; live refresh of open screens. |
| Backend logic | SQL functions behind row-level security, pg_cron, pg_net | Every read and write the app makes; reminders, expiry and day-after checks on a schedule; the push webhook. |
| Edge Functions | Deno (TypeScript) | Push delivery over APNs, account deletion, Sign in with Apple token exchange, report emails. |
| Device frameworks | APNs, EventKit, MapKit, Contacts, Core Location | Notifications, calendar busy times, court search and directions, contact matching, the player's area. |
| Website | Static HTML, CSS and JavaScript on Vercel | Landing page, privacy policy, terms, support. |
| CI | GitHub Actions | Simulator builds and the unit tests on every app change; migrations and the smoke test on Postgres 16 for backend changes; the dev deploy on merge. |

## Project structure

| Path | What |
|---|---|
| `ios/Courtly.xcodeproj` | Open this in Xcode 26 or newer. |
| `ios/Courtly/App` | App entry, root view, session state, notification delegate. |
| `ios/Courtly/Config` | Supabase URLs and keys per environment, policy links. |
| `ios/Courtly/DesignSystem` | Color and type tokens, shared components (cards, pills, buttons, avatars). |
| `ios/Courtly/Features` | One folder per screen group: Onboarding, Main (tab shell, stores), Play, Hits, Chat, People, You. |
| `ios/Courtly/Models` | Plain data types matching the backend's JSON shapes. |
| `ios/Courtly/Services` | Supabase client, typed `API` wrappers, device services (location, calendar, contacts, notifications), snapshot cache. |
| `ios/CourtlyTests` | Unit tests (XCTest): deep links, error messages, date decoding, the availability grid, model decoding. |
| `supabase/migrations` | The schema, row-level security, and every database function the app calls, in order. |
| `supabase/functions` | Edge Functions: `send-push`, `delete-account`, `apple-token-exchange`, `report-email` (emails each report to the support inbox). |
| `supabase/seed` | Public courts and the blocked-words list. |
| `supabase/demo` | The demo world: four demo players and everything the App Review account sees, rebuilt by the deploy's `demo` step. |
| `supabase/reviewer` | The App Review account: create or update, and remove. |
| `supabase/tests` | The smoke test that runs after each deploy, the reviewer-side check of the demo world, and a local Postgres harness. |
| `scripts/supabase-deploy.mjs` | Deploys migrations, seeds, settings, secrets and functions through the Supabase management API. |
| `scripts/testflight.sh` | Archives the Release app and uploads it to TestFlight with an App Store Connect API key. |
| `site/` | Landing page, privacy policy, terms and support pages. Vercel root directory is `site`. |
| `docs/moderation.md` | How reports are handled day to day. |
| `.github/workflows` | iOS build and tests, backend test, backend deploy. |

## Getting started

You need a Mac with Xcode 26 or newer (the app uses the iOS 26 SDK's age-range check). Nothing else has to be installed to run the app in the simulator: Debug builds talk to the shared `courtly-dev` project with the public key in `AppConfig.swift`, and that key only works under the database's row-level security. Running on a phone needs your own Apple developer team. The backend harness needs Postgres 16 and `psql`.

```sh
git clone https://github.com/Charanjarugula/Congressional_app_challenge.git
cd Congressional_app_challenge
open ios/Courtly.xcodeproj
```

Select an iPhone simulator and press Run. Debug builds talk to the `courtly-dev` Supabase project, Release builds to `courtly-prod` (see `ios/Courtly/Config/AppConfig.swift`). The project uses Xcode's synchronized folders, so new files added under `ios/Courtly` are picked up automatically.

To run on a device, choose your team under Signing & Capabilities. The bundle id is `com.charanjarugula.courtly`.

### Building and testing

CI builds the app for the simulator in Debug and Release without signing:

```sh
xcodebuild build -project ios/Courtly.xcodeproj -target Courtly -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO
```

The backend's migrations, seed and smoke test run against a local Postgres 16. The harness drops and recreates a database named `courtly_test`, so point it at a server you can scratch:

```sh
PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres supabase/tests/local/run.sh
```

## How the app talks to the backend

Every read and write is one database function (`get_play_feed`, `create_hit`, `send_message`, ...) called through `API.swift`. Row-level security guards direct table access; the functions run as security definer and check the caller themselves. Only those entry points are callable over the API: helpers such as `hit_json` or `chat_json` have no grant, so a new function the app should call needs `grant execute ... to authenticated` in its migration (see `0009_function_grants.sql`). The row policies take the caller from the session through the `viewer_*` wrappers (`0011_review_fixes.sql`); the two-player helpers such as `is_blocked_either` and `is_chat_member` are not callable by the app role, and neither is the `chats` table, which the app only ever reads through `chat_json`. Errors raised as short codes (`hit_full`, `already_requested`) are turned into plain sentences in `BackendMessages.swift`.

Play, My Hits, the People list and the profile keep the last response on disk so they paint before the network answers. Open chats, the People list and the hit tabs listen over Supabase Realtime (`RealtimeHub.swift`, one connection for the app) for rows they are allowed to see and refresh at once; a slow poll stays on as the fallback.

## Deploying the backend

A push to `main` that touches `supabase/`, the deploy script or the workflow deploys the **dev** project with the default steps (`check migrate seed settings auth secrets functions test status`). Prod is deployed only by hand: run the **Backend deploy** workflow (Actions tab) with target `prod`. The workflow takes a target (`dev` or `prod`) and the steps to run. Repository secrets it reads: `SUPABASE_ACCESS_TOKEN` (required), `WEBHOOK_SECRET` and `REVIEWER_PASSWORD` (keep the push webhook and the App Review account in agreement with what is deployed), `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_PRIVATE_KEY` (push and Sign in with Apple), `GOOGLE_CLIENT_ID`, `SMTP_USER` and `SMTP_PASS` (email codes and report emails through Gmail; after changing them, run the `auth` and `secrets` steps on both projects so sign-in codes and report emails use the same password). `scripts/supabase-deploy.mjs` lists which step uses which. Optional steps: `reviewer` and `reviewer-remove` for the App Review account, `demo` and `demo-remove` for the world it sees (friends, chats, requests, hits); run `demo` on prod before submitting to App Review and `demo-remove` before launch. `DEMO_PASSWORD`, when set, is the demo players' sign-in password. `status` prints one line per fact about the deployed project (migrations recorded, cron jobs, grants, counts) without changing anything.

### Auth configuration

Email sign-in sends a six-digit code, so the Supabase project needs: OTP length 6 and expiry 600 s; the Magic Link and Confirm signup templates containing `{{ .Token }}`; and an SMTP server (the built-in mailer allows two emails an hour). Sign in with Apple needs the Apple provider enabled with the bundle id as client id; Google needs the iOS client id. The deploy's `auth` step sets all of this from the secrets above when the access token has the auth-config scope, and prints the values to set by hand in Authentication → Email and Providers when it doesn't.

Pull requests that touch `supabase/` run the migrations and the smoke test against a throwaway Postgres in CI; the run fails if any function in the schema went unexecuted, so a new function needs a check in `supabase/tests/smoke.sql`. Migrations are append-only once a project has recorded them in `private.app_migrations`: a change to a function is a new numbered file that re-creates it (`0010_…`, `0011_…`), never an edit to a file already applied, so `migrate` can tell what is new. The deploy enforces it: `migrate` records a hash of each file it applies and refuses to run when a recorded file's contents have changed. A project whose ledger predates hash tracking is refused too, because nothing proves it received the files as they read today: reset it once with the dev-only `reset` step, which asks the catalogs for everything the migrations created and takes it all out (tables, functions, types, cron jobs, the private schema, the avatars policies, and the accounts, since a sign-in without its profile row could never get one back), so `migrate` runs every file again from nothing. Only when the applied files are known to match the project, `migrate --adopt-hashes` records the current hashes instead. `reset` refuses any project but dev.

## Roadmap and known limitations

Planned, with no dates attached: the App Store release, after the current TestFlight testing.

Limitations today: courts are the 25 seeded Palm Beach County public courts plus the ones players add; iOS 17 and later only, no Android; phone numbers are not collected, so friends are found by email or by adding each other; English only.

## Credits

Built by Charan Jarugula and Maddox Tse. Thanks to [Supabase](https://supabase.com) for the backend platform, Apple for SwiftUI and the device frameworks, and the Nunito typeface, used on the website under the SIL Open Font License (`site/fonts/OFL.txt`).

## Working in this repo

- Branch from `main` and open a pull request. Nothing is pushed to `main` directly.
- Keep pull request descriptions short: Summary, Setup, What Changed, Test Plan.
- CI builds the app for the iOS Simulator on every push that touches `ios/`.

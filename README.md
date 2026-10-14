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
| `supabase/tests` | The smoke test that runs after each deploy, and a local Postgres harness. |
| `scripts/supabase-deploy.mjs` | Deploys migrations, seeds, settings, secrets and functions through the Supabase management API. |
| `site/` | Privacy policy, terms and support pages. Vercel root directory is `site`. |

## Running the app

```sh
open ios/Courtly.xcodeproj
```

Select an iPhone simulator and press Run. Debug builds talk to the `courtly-dev` Supabase project, Release builds to `courtly-prod` (see `ios/Courtly/Config/AppConfig.swift`). The project uses Xcode's synchronized folders, so new files added under `ios/Courtly` are picked up automatically.

To run on a device, choose your team under Signing & Capabilities. The bundle id is `com.courtly.ios`.

## How the app talks to the backend

Every read and write is one database function (`get_play_feed`, `create_hit`, `send_message`, ...) called through `API.swift`. Row-level security guards direct table access; the functions run as security definer and check the caller themselves. Errors raised as short codes (`hit_full`, `already_requested`) are turned into plain sentences in `BackendMessages.swift`.

The Play and My Hits tabs keep the last response on disk so they paint before the network answers. Chats poll every few seconds while open.

## Deploying the backend

The **Backend deploy** workflow (Actions tab) takes a target (`dev` or `prod`) and the steps to run. It needs the `SUPABASE_ACCESS_TOKEN` repository secret. Function secrets (APNs key, Apple sign-in key, Gmail app password) are set the same way; `scripts/supabase-deploy.mjs` lists them.

Pull requests that touch `supabase/` run the migrations and the smoke test against a throwaway Postgres in CI.

## Working in this repo

- Branch from `main` and open a pull request. Nothing is pushed to `main` directly.
- Keep pull request descriptions short: Summary, Setup, What Changed, Test Plan.
- CI builds the app for the iOS Simulator on every push that touches `ios/`.

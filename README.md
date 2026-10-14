# Courtly

iOS app that helps adult recreational tennis players in Palm Beach County get on court. The unit is a **hit**: one time, one public court, one format, one or more open spots. Post an open hit or invite someone; when accepted it is confirmed and a chat opens. Four tabs: Play, My Hits, People, You.

## Stack

SwiftUI (iOS 17+), Supabase (Postgres, Auth, Realtime, Storage, Edge Functions), Apple Push Notifications, EventKit, MapKit.

## Repository

| Path | What |
|---|---|
| `ios/Courtly.xcodeproj` | Open this in Xcode 16 or newer. |
| `ios/Courtly/App` | App entry, root view, session state. |
| `ios/Courtly/DesignSystem` | Color and type tokens, shared components. |
| `ios/Courtly/Features` | One folder per feature (Onboarding, Main). |
| `ios/Courtly/Models` | Plain data types shared across features. |
| `ios/Courtly/Services` | Auth boundary and device services (location, calendar, contacts, notifications). |
| `supabase/` | Backend (coming). |

## Running

```sh
open ios/Courtly.xcodeproj
```

Select an iPhone simulator and press Run. The project uses Xcode's synchronized folders, so new files added under `ios/Courtly` are picked up automatically.

To run on a device, choose your team under Signing & Capabilities. The bundle id is `com.courtly.ios`.

## Working in this repo

- Branch from `main` and open a pull request. Nothing is pushed to `main` directly.
- Pull request descriptions follow `.github/pull_request_template.md`.
- CI builds the app for the iOS Simulator on every push that touches `ios/`.

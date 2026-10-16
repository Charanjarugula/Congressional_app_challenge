# Courtly iOS app

The SwiftUI app (iOS 17+). Open `Courtly.xcodeproj` in Xcode 26 or newer (the app uses the iOS 26 SDK); the `Courtly` folder is a synchronized folder, so files added on disk appear in the project.

- Run: pick an iPhone simulator and press Run. Debug builds talk to the `courtly-dev` Supabase project, Release builds to `courtly-prod` (`Courtly/Config/AppConfig.swift`, public keys only).
- Test: press ⌘U, or from the repository root run the `xcodebuild test` line CI uses (see `.github/workflows/ios.yml`). The `Courtly` scheme runs unit tests; choose the `CourtlyUITests` scheme for the UI suite.
- Device: choose your team under Signing & Capabilities; the bundle id is `com.charanjarugula.courtly`.
- Screenshots: the `CourtlyUITests` target has one test that signs in as the App Review account, walks app screens and saves a PNG of each for review. The "README screenshots" workflow (Actions → README screenshots → Run workflow) runs it on a simulator and uploads the PNGs as an artifact; ⌘U skips it unless `SCREENSHOT_DIR` and `REVIEWER_PASSWORD` are set in the scheme's environment.
- TestFlight: `scripts/testflight.sh` archives and uploads with an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, optional `ASC_KEY_PATH`).

How the app talks to the backend, and the folder layout, are in the [root README](../README.md).

### Testing with TestFlight users

The default **Courtly** scheme runs Debug against the development Supabase project. Development accounts and hits are separate from TestFlight's production data. To use the same accounts and listings as TestFlight in the simulator, select **Courtly Production** (Release) in Xcode. Use a separate simulator for production and sign in there; do not copy development sessions. Actions in this scheme affect real production data.

### Two-account interaction check

Use two separate simulators and dedicated accounts on the **same backend**. Install the same candidate build on each. Set both profile areas to Wellington, FL (33414); simulated GPS alone does not change a saved profile area. Keep both apps visible and reverse the roles for the second pass.

| Check | Account A | Expected on account B |
|---|---|---|
| Player discovery | Search B before friendship | A is also searchable by name; no distance-dependent exclusion from name search |
| Public hit | Post a future public hit with available spots | Appears in Explore → All hits; detail matches court, time, format and capacity |
| Joining | Accept B's request | B becomes a participant, capacity decreases once, hit chat becomes available |
| Friendship | Send, cancel, resend a friend request | Each state appears correctly; accepting establishes friendship on both sides |
| Friends feed | Post a friends-only hit | Appears in Explore → Friends after acceptance; excluded for unrelated accounts |
| Invitation | Invite B to a multi-spot hit | Accept once; no remaining reply prompt or invite badge; reopening/repeating acceptance adds no extra participant |
| Messaging | Send distinct messages in DM and hit chat | Delivered once, in order, with unread state clearing when opened; reply works in reverse |
| Synchronization | Edit/cancel a test hit; leave and rejoin where permitted | Details and participation update in both apps without relaunch; refresh recovers if live connection is interrupted |
| Distance | Put the other account/court beyond the selected distance | Any distance includes the eligible hit; an explicit limit excludes it in All hits and Friends |
| Persistence | Background/reopen each app | Friendship, messages and hit state persist; stale requests do not return |

Record the candidate commit, backend, simulator IDs, observed results and screenshots. A fixture UI test or SQL smoke test does not replace this walkthrough. Cancel the test hits and withdraw pending test requests afterward. Do not delete accounts or alter unrelated users' data as cleanup.

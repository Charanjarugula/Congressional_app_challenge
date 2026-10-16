# Courtly iOS app

The SwiftUI app (iOS 17+). Open `Courtly.xcodeproj` in Xcode 26 or newer (the app uses the iOS 26 SDK); the `Courtly` folder is a synchronized folder, so files added on disk appear in the project.

- Run: pick an iPhone simulator and press Run. Debug builds talk to the `courtly-dev` Supabase project, Release builds to `courtly-prod` (`Courtly/Config/AppConfig.swift`, public keys only).
- Test: press ⌘U, or from the repository root run the `xcodebuild test` line CI uses (see `.github/workflows/ios.yml`). The `CourtlyTests` target holds the unit tests.
- Device: choose your team under Signing & Capabilities; the bundle id is `com.charanjarugula.courtly`.
- Screenshots: the `CourtlyUITests` target has one test that signs in as the App Review account, walks the screens shown in the root README and saves a PNG of each. The "README screenshots" workflow (Actions → README screenshots → Run workflow) runs it on a simulator and uploads the PNGs as an artifact; ⌘U skips it unless `SCREENSHOT_DIR` and `REVIEWER_PASSWORD` are set in the scheme's environment.
- TestFlight: `scripts/testflight.sh` archives and uploads with an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, optional `ASC_KEY_PATH`).

How the app talks to the backend, and the folder layout, are in the [root README](../README.md).

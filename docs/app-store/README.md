# App Store launch

Courtly’s first release is free, U.S.-only, and for players 18 and older. The listing is Ready for Review in a draft submission; it has not been submitted to Apple. Release is manual so approval does not publish the app unexpectedly.

## Listing assets

- `en-US.json`: English listing copy and public URLs. Review contact details and sign-in codes belong only in App Store Connect, never this repository.
- [Figma launch page](https://www.figma.com/design/LR6Kq67WXL07ixTesgCwvC/Courtly?node-id=101-6): editable screenshot compositions and shipping app icon.
- App icon: `ios/Courtly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 × 1024, opaque. Apple reads this from the selected build.
- Screenshot exports must show the current app with fictional demo accounts. Do not publish personal chats, test-account emails, or sign-in codes.

Screenshots are required; a video app preview is optional. Use five clear screenshots showing Explore, filters, planning, My Hits, and chat. Export opaque JPGs from Figma at 1320 × 2868 and 1206 × 2622. Do not distort the app captures when fitting device frames.

## Review access

Use `reviewer@courtly.app`. Its fixed eight-digit production code goes in App Store Connect’s password field. The reviewer enters it on the email-code screen; no email is sent for this account. Ordinary users receive six-digit email codes. The code must be tested against production, not just the development project.

Refresh demo hits before submission if they have moved into history. Keep the backend and review account available throughout review. Explain the demo content and the app’s account, location, moderation, and deletion flows in Review Notes. Test deletion with a separate disposable account; do not delete the reviewer account.

## Submission gate

- [x] Five screenshots exported from Figma at each of two iPhone sizes, visually inspected, uploaded, and processed (`COMPLETE`, no errors).
- [x] Build `202610161852` selected, processed as VALID / APP_STORE_ELIGIBLE, and available in TestFlight; icon and privacy manifest verified in its archive.
- [x] Production review account signs in with the exact code saved in App Store Connect; `get_me` returns HTTP 200.
- [x] Privacy label published with owner approval; manifest updated to match. Deploy the policy changes in this PR before submission.
- [x] 18+ override retained; age assurance declared for the existing Declared Age Range integration; content rights confirmed by owner and saved. Archive declares no non-exempt encryption.
- [x] Free price and U.S.-only availability saved. Mac and Vision Pro distribution disabled for this iPhone-focused launch.
- [x] Free Apps Agreement is Active in App Store Connect. No new agreement accepted.
- [x] Charan confirmed access to the support inbox and daily monitoring; moderation procedure documented.
- [x] Both production reports reviewed under owner authorization and marked `reviewed`; no suspension warranted.
- [ ] New-user, returning-user, report/block, account deletion, and permission-denial journeys verified on the final build.
- [ ] User approves the finished listing and authorizes submission to Apple.

## Privacy mapping

All categories below are linked to the account and are not used for advertising tracking. App Functionality applies throughout. Product Personalization also applies to approximate area, friendships, and preferences used for discovery/suggestions.

| Data | Evidence and purpose |
| --- | --- |
| Name and email | Authentication and player profiles. Public player cards currently use first name and last initial. |
| Coarse location | Profile’s city/ZIP centroid or rounded coordinates; nearby discovery. |
| Precise location | User-selected hit/court map coordinates stored with the plan; not continuous device tracking. |
| Contacts | Stored friendships/social graph. Address-book email hashes are processed for matching and discarded, but the social graph is retained. |
| Photos or videos | Optional profile photo. The app currently uploads photos, not video. |
| Emails or text messages | Direct, group, and hit chat content. |
| Customer support | Reports and information submitted for assistance. |
| Other user content | Hit details and other player-authored content. |
| Other data | Birthday/age eligibility, tennis preferences, availability, and optional free/busy flags. |
| User ID | Account identity, relationships, access controls. |
| Device ID | Push notification token, linked to the signed-in account. |

The archive manifest and App Store privacy questionnaire are separate declarations. Changing one does not update the other. Reassess disclosures when removing calendar features or changing location storage. Server/provider diagnostics and retention must also be considered when reviewing the final label.

## Evidence

2026-10-16 production check: [backend run](https://github.com/Charanjarugula/Congressional_app_challenge/actions/runs/38949610819) passed smoke tests; 29 migrations recorded through `0032_start_time_only.sql`; no failed cron runs in the preceding 24 hours. Review account present. The audit found no moderator account and two open reports. Support email delivery was confirmed in the inbox; both production reports have since been reviewed and marked `reviewed`. No player was suspended.

## Apple references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): completeness, reviewer access, accurate metadata, user-generated content, privacy.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/): accepted dimensions, formats, scaling, and no alpha channels.
- [Product page guidance](https://developer.apple.com/app-store/product-page/): descriptions, subtitle, keywords, screenshots, and optional previews.
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/): disclose collected data, purposes, linkage, and tracking.
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/): in-app deletion and Sign in with Apple token revocation.

These checks reduce avoidable rejection risks; Apple makes the review decision.

## Candidate verification — 2026-10-16

- Debug build and all 59 unit tests passed locally.
- Signed Release archive `202610161852` succeeded; bundled icon, iPhone device family, export-compliance flag, and updated privacy manifest verified.
- [Screenshot walkthrough](https://github.com/Charanjarugula/Congressional_app_challenge/actions/runs/38949220381) passed against the development demo account. Filters captured locally from the real SwiftUI view.
- [Production reviewer reset](https://github.com/Charanjarugula/Congressional_app_challenge/actions/runs/38951444188) succeeded. Code stays in GitHub Secrets and App Store Connect only.
- `screenshots/iphone-large` and `screenshots/iphone-medium` contain the uploaded Figma exports, ordered 01–05.
- No app behavior or backend schema changed in this release-preparation PR. Earlier device testing does not replace a final candidate check.

# Courtly recording accounts

This branch connects a normal **Debug** build to Courtly's hosted development backend. The fictional data is already populated. Both accounts see the same server, including when run on different Macs. Docker, Supabase credentials and database setup are **not** needed by the person recording.

## Start recording

You need Xcode with an installed iOS simulator runtime, Python 3, and access to this repository.

```sh
git fetch origin
git switch demo/shared-recording
python3 scripts/shared-recording/run.py
```

The script builds the app and opens two dedicated simulators. On each one, choose **I already have an account**, enter the email below, then enter the corresponding **8-digit code from Charan's private login sheet** in the email-code field. No email is sent for these two accounts.

| Simulator | Email |
|---|---|
| Ana Ruiz | recording.ana@courtly.app |
| Luis Morales | recording.luis@courtly.app |

You can also open `ios/Courtly.xcodeproj`, select the Courtly scheme and run **Debug** on any supported simulator. These recording logins do not work in the existing TestFlight/App Store build, which connects to production. Use this branch, not `main`.

## Suggested walkthrough

1. On Ana, browse Explore around Wellington, filter by time/format/level, and switch All hits/Friends.
2. Open hit details and show the court, host and joining options.
3. Show Ana's incoming requests from Priya and Sarah and outgoing friend request to Nina in People.
4. Open Ana and Luis's direct conversation on both simulators; send a message and reply from the other account.
5. On Ana, open Needs your reply and accept Luis's request to the casual hit. Check My Hits on Luis.
6. Show upcoming hits, a confirmed shared hit, past activity and the Wellington Weekend Crew group conversation with its hit invitation.
7. Create a new hit on one account and refresh Explore on the other.

The fixture starts with eight fictional adults, twenty hits, four pending friend requests, multiple conversations and a group invitation. Dates are relative to October 24, 2026; ask Charan to refresh the fixture if recording later. Activity is shared: accepting a request consumes it for everyone using these accounts. Coordinate filming, and do not reset while someone else is recording.

## Isolation and limitations

- Production and `reviewer@courtly.app` are untouched. Do not share App Review credentials.
- The hosted development environment is shared with development users; it is not a separate production service. Keep recording interactions among the fictional players.
- Real authentication, database rules, messaging and hit actions are used. This is not a static mockup.
- Simulator push notifications, Apple/Google authentication, and physical-device behavior are separate from this recording setup. Use the provided email sign-in.
- Codes are private, are not in Git, and should not appear in the video. No administrative credentials are required to record.

## Maintainer tools

`seed.py` creates the fixture once on the hardcoded development project and refuses to overwrite existing recording accounts. It deliberately does not call the existing demo/reviewer seeder. `verify.py` checks both logins, populated RPC results, invalid-code rejection and two-way chat; it adds two ordinary messages. Both scripts read private codes from ignored `.recording/shared-credentials.json` on the maintainer's Mac. Neither is needed by the recorder.

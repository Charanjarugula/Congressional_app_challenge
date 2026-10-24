# Figures

Interactive drawings of how Courtly works on the inside, each built as a small machine whose motion is the mechanism. Every number and phase in a figure comes from the code it names, and the figure's own model (`model.mjs`) is the single source for the parts, the readout and the caption.

| Figure | What it explains | True to |
| --- | --- | --- |
| [`whole-machine/`](whole-machine/) | Every station on one bench and one call walking through: the API door into the database, row-level security and the SQL functions, Realtime carrying the insert back out, pg_cron calling functions on its own clock, and the four Edge Functions, with send-push handing a notification to APNs for a phone that is closed. | `0002_security.sql`, the functions in `supabase/migrations`, the Realtime publication and `RealtimeHub.swift`, the `cron.schedule` calls (`0008_scheduler.sql` and later), `supabase/functions/*` |
| [`last-spot/`](last-spot/) | How a hit fills: the row lock that makes two accepts take turns, the hit confirming and opening its chat in one transaction, the full hit turning later requests away, and the scheduler's five-minute tick sending the hour-before reminder once. | `respond_to_request` and `add_player` (`supabase/migrations/0004_hits_rpc.sql`, `0016_one_chat_per_hit.sql`), `run_hit_scheduler` (`0008_scheduler.sql`) |
| [`everyone-hears-it/`](everyone-hears-it/) | How a chat message reaches every member: the hollow copy the sender sees at once, the checks `send_message` makes in order, the stored row stamped with an id, one insert ringing every socket allowed to see it, polling for a phone whose socket is down, a push for a phone that is away, and a repeated `client_id` returning the stored row instead of a second one. | `send_message` and `post_message` (`supabase/migrations/0016_one_chat_per_hit.sql`, `0011_review_fixes.sql`), the Realtime publication (`0002_security.sql`), `RealtimeHub.swift`, `ChatThreadView.swift`, `notify` and `post_push` (`0008_scheduler.sql`) |
| [`posting-a-hit/`](posting-a-hit/) | What happens to a posted hit: `create_hit`'s limits, the row stored, then `get_play_feed` building each viewer's list from friendship, the distance from the court to their home point and their busy hours, and two Play tabs refreshing once after the insert. | `create_hit` and `check_rate_limit` (`supabase/migrations/0016_one_chat_per_hit.sql`), `get_play_feed`, `feed_candidate`, `busy_at` (`0026_feed_distance.sql`, `0023_review_readiness.sql`, `0025_completion.sql`), the gist index on `courts.point` (`0001_schema.sql`), the refresh debounce (`MainTabView.swift`) |
| [`opening-the-app/`](opening-the-app/) | What the app does at launch: the keychain's tokens checked, every tab painted from its snapshot on disk before the network answers, the fresh copies replacing them and being saved back, and a burst of Realtime changes becoming one refresh after a 400 ms timer. | `AppSession.restore()` (`ios/Courtly/App/AppSession.swift`), `SnapshotCache.swift`, `HitsStore.init` and `InboxStore.init`, the subscriptions and `scheduleHitsRefresh` (`MainTabView.swift`) |

Open a figure's `index-light.html` or `index.html` in a browser. Hover to scrub through the story, press space to play or pause, use the arrow keys to step. The figure stops when it is off screen and stays still under "reduce motion".

## Rebuilding

Each figure is a Node script that writes its page next to itself, with the drawing kit in `kit/` (from [Anatomy](https://github.com/wheresryan22/anatomy), MIT) inlined so the page has no dependencies.

```
node docs/figures/last-spot/build.mjs            # index.html, dark
node docs/figures/last-spot/build.mjs --light    # index-light.html
node docs/figures/everyone-hears-it/build.mjs    # and --light, the same way
node docs/figures/posting-a-hit/build.mjs --audit # also checks the pipes' geometry
node docs/figures/opening-the-app/build.mjs --audit
node docs/figures/whole-machine/build.mjs --audit
```

The build checks that the story ends where the caption says it does and fails otherwise. Figures with pipes draw through `kit/parts.mjs`, which records every part for the kit's audit; `--audit` must end `audit passed`. `<name>.png` is the light page captured at 2× for the README.

## Rendering a clip

`render.mjs` plays a figure's story frame by frame in headless Chromium and writes an MP4 (1920×1080, 30 fps, the card centred on the page's own background), so the same drawing can go into a video. It needs [Playwright](https://playwright.dev) with its Chromium and `ffmpeg` on the PATH.

```
npm install -g playwright && npx playwright install chromium
PLAYWRIGHT_PATH="$(npm root -g)/playwright" node docs/figures/render.mjs docs/figures/last-spot/index.html out/last-spot.mp4
```

`--fps`, `--hold` (seconds of the last frame to append, default 1.5), `--width` and `--height` adjust the output. The page's `window.__story.seek(t)` places every frame, so a render is deterministic.

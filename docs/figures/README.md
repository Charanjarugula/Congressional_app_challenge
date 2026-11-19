# Figures

Interactive drawings of how Courtly works on the inside, each built as a small machine whose motion is the mechanism. Every number and phase in a figure comes from the code it names, and the figure's own model (`model.mjs`) is the single source for the parts, the readout and the caption.

| Figure | What it explains | True to |
| --- | --- | --- |
| [`last-spot/`](last-spot/) | How a hit fills: the row lock that makes two accepts take turns, the hit confirming and opening its chat in one transaction, the full hit turning later requests away, and the scheduler's five-minute tick sending the hour-before reminder once. | `respond_to_request` and `add_player` (`supabase/migrations/0004_hits_rpc.sql`, `0016_one_chat_per_hit.sql`), `run_hit_scheduler` (`0008_scheduler.sql`) |

Open a figure's `index-light.html` or `index.html` in a browser. Hover to scrub through the story, press space to play or pause, use the arrow keys to step. The figure stops when it is off screen and stays still under "reduce motion".

## Rebuilding

Each figure is a Node script that writes its page next to itself, with the drawing kit in `kit/` (from [Anatomy](https://github.com/wheresryan22/anatomy), MIT) inlined so the page has no dependencies.

```
node docs/figures/last-spot/build.mjs            # index.html, dark
node docs/figures/last-spot/build.mjs --light    # index-light.html
```

The build checks that the story ends where the caption says it does and fails otherwise. `<name>.png` is the light page captured at 2× for the README.

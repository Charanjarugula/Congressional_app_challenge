// Posting a hit, as a pure function of time. The numbers are the backend's: create_hit refuses a
// start under 15 minutes away or over 30 days out, spots outside 1–7, and more than 20 hits a day
// per host (0016_one_chat_per_hit.sql, check_rate_limit); the row goes into hits with
// spots_open = spots and status 'open'; get_play_feed (0026_feed_distance.sql) then builds every
// viewer's list on request: feed_candidate (open, spots left, in the future, host not blocked,
// visibility 'anyone' with a host who allows anyone, or 'friends' and a friend), busy_at (the
// viewer's availability mask for that hour), and st_distance from the court to the viewer's home
// point for the Near you order, over the gist index on courts.point. Phones with the Play tab open
// hear the insert over Realtime and refresh once after a 400 ms debounce (MainTabView.swift).

export const LOOP = 18;
export const SPOTS = 2;
export const LIMITS = ["≥ 15 min ahead", "≤ 30 days out", "1–7 spots", "≤ 20 a day"];
export const GATE_AT = [0.2, 0.4, 0.6, 0.8];
export const DEBOUNCE_MS = 400;

// The three viewers the sorter looks at, in order, and what the function decides for each.
export const VIEWERS = [
  { name: "Ana", friend: true, miles: 3.4, busy: false, tray: "friends" },
  { name: "Luis", friend: false, miles: 2.1, busy: false, tray: "near" },
  { name: "Priya", friend: false, miles: 1.2, busy: true, tray: "out" },
];

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (a, b, t) => { const x = clamp01((t - a) / (b - a)); return x * x * (3 - 2 * x); };
const along = (t, t0, t1) => (t >= t0 && t <= t1 ? smooth(t0, t1, t) : null);
const near = (share, at, w) => (share === null ? 0 : clamp01(1 - Math.abs(share - at) / w));

export function storyAt(time) {
  const t = ((time % LOOP) + LOOP) % LOOP;
  const pulses = { post: null, toSorter: null, toAna: null, toLuis: null };
  let stored = 0, gearTurn = 0, dial = 0, mask = 0, flap = 0, screens = { host: 1, ana: 0, luis: 0 }, debounce = 0, note = "";
  const cards = VIEWERS.map(() => ({ x: 0, tray: null }));   // x: 0 at the start of the sorter rail, 1 at the test station, 2 in a tray

  // 1. The post leaves the host's phone and passes the four limits.
  pulses.post = along(t, 1.0, 5.4);
  const gates = GATE_AT.map((at) => near(pulses.post === null ? null : (pulses.post - 0.45) / 0.55, at, 0.12));
  if (t >= 5.4) stored = 1;

  // 2. The feed function looks at each viewer in turn. The gears turn while it runs.
  const SORT_T0 = 6.0, PER = 2.0;
  if (t >= SORT_T0 && t < SORT_T0 + VIEWERS.length * PER + 0.5) gearTurn = (t - SORT_T0) * 1.2;
  else if (t >= SORT_T0) gearTurn = (VIEWERS.length * PER + 0.5) * 1.2;
  VIEWERS.forEach((v, i) => {
    const t0 = SORT_T0 + i * PER;
    const card = cards[i];
    card.x = smooth(t0, t0 + 0.6, t);                             // roll to the test station
    if (t >= t0 + 0.6 && t < t0 + 1.4) {
      const s = smooth(t0 + 0.6, t0 + 1.0, t);
      dial = Math.max(dial, s * (v.miles / 5));                   // the distance arm swings out to the miles
      mask = Math.max(mask, v.busy ? s : 0);                       // the busy mask slides over a busy viewer
      flap = Math.max(flap, v.friend ? s : 0);                     // the friends flap lifts for a friend
    }
    if (t >= t0 + 1.4) { card.x = 1 + smooth(t0 + 1.4, t0 + 2.0, t); card.tray = v.tray; }
  });

  // 3. Two phones have Play open: the insert reaches them, and one debounced refresh paints the hit.
  pulses.toAna = along(t, 12.2, 13.2);
  pulses.toLuis = along(t, 12.2, 13.2);
  debounce = smooth(13.2, 13.6, t);
  if (t >= 13.6) { screens.ana = 1; screens.luis = 1; }

  if (t < 1.0) note = `Plan a hit · ${SPOTS} spots · Sat 10:00 · Wellington`;
  else if (t < 3.0) note = "create_hit(court, starts_at, format, spots, visibility)";
  else if (t < 5.4) note = LIMITS.join(" · ");
  else if (t < 6.0) note = "stored · status open · spots_open = 2";
  else if (t < 8.0) note = "Ana · a friend · free Saturday → From friends";
  else if (t < 10.0) note = "Luis · 2.1 mi from the court · free → Near you";
  else if (t < 12.0) note = "Priya · busy at 10:00 → not shown";
  else if (t < 13.6) note = `two Play tabs hear the insert · one refresh after ${DEBOUNCE_MS} ms`;
  else note = "one SQL function · spatial index · no cache";

  return { t, pulses, gates, stored, gearTurn, dial, mask, flap, cards, screens, debounce, note };
}

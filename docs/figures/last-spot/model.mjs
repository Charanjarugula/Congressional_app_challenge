// The story the figure plays, as a pure function of time. Every number here is the backend's:
// a hit has 1–7 spots (this one has 2); respond_to_request locks the hit row, then the request row,
// so two accepts on the same hit queue up (0004_hits_rpc.sql); add_player takes one spot, marks the
// hit confirmed on the first player and opens its chat in the same transaction, and once spots_open
// reaches 0 every other pending request expires with "filled up before the host could answer you"
// (0016_one_chat_per_hit.sql); run_hit_scheduler runs every 5 minutes and sends the one-hour
// reminder once, because the step is "due and not yet sent" (0008_scheduler.sql).

export const SPOTS = 2;
export const LOOP = 18;          // seconds of story before it starts over
export const TICK_MINUTES = 5;   // pg_cron: */5 * * * *

// Where a token is along the rail (x), how far it has dropped into its seat (z, 0 or SEAT_DROP), and
// where it stands in y. Tokens travel along the rail at y = RAIL_Y and sit in the tray's seats.
export const RAIL_Y = -38;
export const QUEUE_X = [136, 118, 100];   // where the three players start
export const GATE_X = 53;                 // a token's centre when it rests against the bolt
export const SEAT_X = [-19, 21];          // the two seats, far one first
export const SEAT_DROP = 1.5;
export const BOLT_TRAVEL = 20;            // how far the bolt slides open, in y
export const FLAG_RISE = 20;

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (a, b, t) => { const x = clamp01((t - a) / (b - a)); return x * x * (3 - 2 * x); };
const mix = (a, b, s) => a + (b - a) * s;

// A token's x as it rolls from `from` to `to` between t0 and t1.
const roll = (t, t0, t1, from, to) => mix(from, to, smooth(t0, t1, t));

export function storyAt(time) {
  const t = ((time % LOOP) + LOOP) % LOOP;
  const a = { x: QUEUE_X[0], z: 0 };
  const b = { x: QUEUE_X[1], z: 0 };
  const c = { x: QUEUE_X[2], z: 0 };
  let bolt = 0, flag = 0, lamp = 0, spots = SPOTS, ticks = 0, remind = 0, status = "open", note = "";

  // 1. The first player asks and the host accepts.
  a.x = roll(t, 1.0, 3.0, QUEUE_X[0], GATE_X);
  bolt = smooth(3.0, 3.4, t) - smooth(4.9, 5.2, t);               // the row lock: taken, then released
  if (t >= 3.4) a.x = roll(t, 3.4, 4.6, GATE_X, SEAT_X[0]);
  a.z = -SEAT_DROP * smooth(4.6, 4.9, t);
  if (t >= 4.9) { spots = 1; status = "confirmed"; }
  flag = smooth(4.9, 5.6, t);                                      // status = 'confirmed' on the first player
  lamp = t >= 5.6 ? 1 : 0;                                         // ensure_hit_chat ran in the same transaction

  // 2. Two more ask at once. One accept wins the lock; the other waits, then is turned away.
  b.x = roll(t, 6.0, 8.0, QUEUE_X[1], GATE_X);
  c.x = roll(t, 6.0, 8.0, QUEUE_X[2], GATE_X + 16);
  if (t >= 8.0) bolt += smooth(8.0, 8.4, t) - smooth(9.7, 10.0, t);
  if (t >= 8.4) b.x = roll(t, 8.4, 9.4, GATE_X, SEAT_X[1]);
  b.z = -SEAT_DROP * smooth(9.4, 9.7, t);
  if (t >= 9.7) { spots = 0; status = "full"; }
  if (t >= 10.0) {
    const bump = Math.sin(clamp01((t - 10.0) / 0.3) * Math.PI) * 3;   // presses the closed bolt once
    c.x = GATE_X + 16 - bump;
  }
  if (t >= 10.3) c.x = roll(t, 10.3, 12.0, GATE_X + 16, QUEUE_X[2]);

  // 3. The scheduler: a tick every 5 minutes, and the one-hour reminder goes out exactly once.
  if (t >= 12.0) ticks = Math.min(9, Math.floor((t - 12.0) / 0.5) + 1);
  remind = ticks >= 7 ? 1 : 0;

  if (t < 1.0) note = `open · ${SPOTS} spots`;
  else if (t < 3.0) note = "a player asks to join";
  else if (t < 4.9) note = "host accepts · hit row locked";
  else if (t < 6.0) note = "confirmed · 1 of 2 · chat open";
  else if (t < 8.0) note = "two more ask at once";
  else if (t < 9.7) note = "one accept holds the lock · one waits";
  else if (t < 10.3) note = "full · 2 of 2 · spots_open = 0";
  else if (t < 12.0) note = "the other: filled up before the host could answer";
  else if (ticks < 7) note = `scheduler · ${ticks * TICK_MINUTES} min · nothing due`;
  else note = "reminder sent once · 1 hour before";

  return { t, a, b, c, bolt: clamp01(bolt), flag, lamp, spots, status, ticks, remind, note };
}

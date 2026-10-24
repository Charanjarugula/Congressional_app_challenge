// The story the figure plays, as a pure function of time. The numbers are the app's and the
// backend's: ChatThreadView.send() appends the message locally with a fresh client_id before the
// network answers and swaps it for the stored row when send_message returns; send_message
// (0016_one_chat_per_hit.sql) returns the existing row for a repeated client_id, then checks
// membership, blocks, the blocked-words filter and a 30-a-minute rate limit before post_message
// stores the row and notify() queues a push per member; the messages table is in the
// supabase_realtime publication (0002_security.sql), so every phone whose RLS lets it see the row
// hears the insert over its socket (RealtimeHub.swift); a chat screen also polls, every 5 s until
// its channel is delivering and every 20 s after (ChatThreadView.swift); notify() posts to the
// send-push Edge Function through pg_net, which delivers over APNs (0008_scheduler.sql).

export const LOOP = 20;
export const MEMBERS = 5;          // the sender and four others
export const RATE_LIMIT = 30;      // messages a minute
export const POLL_FAST = 5;        // seconds, while the channel is not delivering
export const POLL_SLOW = 20;       // seconds, once it is

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (a, b, t) => { const x = clamp01((t - a) / (b - a)); return x * x * (3 - 2 * x); };
// A pulse's share of its wire between t0 and t1, or null when it is not on the wire.
const along = (t, t0, t1) => (t >= t0 && t <= t1 ? smooth(t0, t1, t) : null);
// Lifts to 1 as the share passes `at`, over a window of `w` either side.
const near = (share, at, w) => (share === null ? 0 : clamp01(1 - Math.abs(share - at) / w));

export const GATES = ["member", "not blocked", "clean words", "under 30/min"];
export const GATE_AT = [0.18, 0.38, 0.58, 0.78];   // where each gate sits along the cabinet path

export function storyAt(time) {
  const t = ((time % LOOP) + LOOP) % LOOP;
  const pulses = { send: null, cabinet: null, toBoard: null, fan: null, toPush: null, radio: null, poll: null, pollBack: null, dupe: null, dupeBack: null };
  const screens = { a: 0, b: 0, c: 0, d: 0, e: 0 };
  let card = 0, press = 0, stored = 0, reader = 0, ticks = 0, note = "";

  // 1. Typed, shown at once, sent.
  if (t >= 2.2) card = 1;                                   // the hollow copy, client_id only
  pulses.send = along(t, 2.4, 4.6);
  pulses.cabinet = along(t, 4.6, 7.4);                      // the checks, in the order the function makes them
  press = Math.sin(clamp01((t - 7.4) / 0.5) * Math.PI);     // post_message: the id is stamped on
  if (t >= 7.9) { stored = 1; card = 2; }                   // the stored row replaces the hollow one
  pulses.toBoard = along(t, 7.9, 9.0);

  // 2. One insert, every socket. One socket is down, so that phone polls.
  pulses.fan = along(t, 9.0, 10.4);
  if (t >= 10.4) screens.a = screens.b = screens.c = 1;
  if (t >= 10.4) ticks = Math.min(8, Math.floor((t - 10.4) / 0.4));
  pulses.poll = along(t, 12.0, 13.0);
  pulses.pollBack = along(t, 13.0, 14.0);
  if (t >= 14.0) screens.d = 1;

  // 3. A phone that is away gets a push: notify → pg_net → send-push → APNs.
  pulses.toPush = along(t, 9.0, 10.2);
  pulses.radio = along(t, 10.2, 11.4);
  if (t >= 11.4) screens.e = 1;

  // 4. The same send again (a retry): the tag is known, the row comes back, nothing is stored twice.
  pulses.dupe = along(t, 14.5, 15.7);
  reader = Math.sin(clamp01((t - 15.7) / 0.6) * Math.PI);
  pulses.dupeBack = along(t, 16.3, 17.5);

  const gates = GATE_AT.map((at) => near(pulses.cabinet, at, 0.12));
  const live = screens.a + screens.b + screens.c;

  if (t < 1.2) note = `a chat with ${MEMBERS} members`;
  else if (t < 2.4) note = "sent · on the sender's screen at once, hollow";
  else if (t < 4.6) note = "send_message(chat, client_id, body)";
  else if (t < 7.4) note = `member? · not blocked? · clean? · under ${RATE_LIMIT}/min?`;
  else if (t < 7.9) note = "stored · id stamped on";
  else if (t < 9.0) note = "the hollow copy becomes the stored row";
  else if (t < 10.4) note = "one insert · every socket that may see it";
  else if (t < 12.0) note = `one socket is down · that phone polls every ${POLL_FAST} s`;
  else if (t < 14.0) note = "poll · the page comes back with the message";
  else if (t < 14.5) note = `1 message · ${live} live · 1 polled · 1 pushed`;
  else if (t < 17.5) note = "sent again · same client_id · returned, not stored twice";
  else note = `1 message · ${live} live · 1 polled · 1 pushed`;

  return { t, pulses, gates, press, reader, card, stored, screens, ticks, note };
}

// Opening the app, as a pure function of time. The facts are the app's: the session tokens live
// in the keychain (Keychain.swift, Session.swift) and AppSession.restore() checks them with
// validSession() and get_me; every tab's store paints from its own snapshot on disk before any
// network answer (SnapshotCache.swift, one folder per account; HitsStore.init loads play_feed and
// my_hits, InboxStore.init loads inbox and friend_requests), and keeps that copy when the backend
// is unreachable (keepWhatTheDeviceHas); fresh loads replace the copies and are saved back; the
// main tabs subscribe to hits, join_requests and messages over Realtime, and every change starts a
// 400 ms timer so a burst of rows becomes one refresh (MainTabView.swift, scheduleHitsRefresh).

export const LOOP = 16;
export const SNAPSHOTS = ["play_feed", "my_hits", "inbox", "friend_requests"];
export const DEBOUNCE_MS = 400;

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (a, b, t) => { const x = clamp01((t - a) / (b - a)); return x * x * (3 - 2 * x); };
const along = (t, t0, t1) => (t >= t0 && t <= t1 ? smooth(t0, t1, t) : null);

export function storyAt(time) {
  const t = ((time % LOOP) + LOOP) % LOOP;
  const beads = { tokens: null, disk: null, net: null, netBack: null, other: null, notice1: null, notice2: null, refresh: null, refreshBack: null };
  const trays = SNAPSHOTS.map(() => 0);     // 0 closed, 1 slid out
  const tiles = SNAPSHOTS.map(() => 0);     // 0 blank, 1 painted from disk, 2 fresh
  let phone = 0, knob = 0, lock = 0, row = 0, timer = 0, bell = 0, refreshes = 0, note = "";

  // 1. Launch: the keychain's tokens are still good.
  phone = t >= 1.0 ? 1 : 0;
  beads.tokens = along(t, 1.0, 1.5);
  knob = smooth(1.5, 2.1, t) * Math.PI / 2;    // the lock turns a quarter
  lock = t >= 2.1 ? 1 : 0;
  beads.disk = along(t, 2.1, 2.5);

  // 2. Four trays slide out; each tab paints from the copy on disk.
  SNAPSHOTS.forEach((_, i) => {
    const t0 = 2.5 + i * 0.4;
    trays[i] = smooth(t0, t0 + 0.5, t) - smooth(5.6 + i * 0.1, 6.0 + i * 0.1, t);   // out, then home again
    if (t >= t0 + 0.4) tiles[i] = 1;
  });

  // 3. The network answers: each tab swaps to the fresh copy, which is saved back.
  beads.net = along(t, 4.4, 5.4);
  if (t >= 5.4) row = 1;
  beads.netBack = along(t, 5.8, 6.8);
  SNAPSHOTS.forEach((_, i) => { if (t >= 6.8 + i * 0.15) tiles[i] = 2; });

  // 4. Another phone changes two rows; two notices, one timer, one refresh.
  beads.other = along(t, 8.6, 9.2);
  beads.notice1 = along(t, 9.2, 9.8);
  beads.notice2 = along(t, 9.6, 10.2);
  bell = (t >= 9.2 && t < 9.5) || (t >= 9.6 && t < 9.9) ? 1 : 0;
  timer = t >= 9.8 ? smooth(9.8, 11.0, t) : 0;                // the 400 ms, slowed so it reads
  if (t >= 10.2 && t < 11.0) timer = smooth(10.2, 11.4, t);   // the second notice restarts it
  beads.refresh = along(t, 11.4, 12.2);
  beads.refreshBack = along(t, 12.4, 13.2);
  refreshes = t >= 13.2 ? 1 : 0;

  if (t < 1.0) note = "tap the icon";
  else if (t < 2.1) note = "keychain → session tokens · validSession()";
  else if (t < 2.5) note = "signed in · profile from disk";
  else if (t < 4.4) note = "snapshots: " + SNAPSHOTS.slice(0, Math.min(4, Math.max(1, Math.floor((t - 2.5) / 0.4) + 1))).join(" · ");
  else if (t < 5.8) note = "every tab painted from disk · get_me · get_play_feed · get_inbox";
  else if (t < 8.6) note = "fresh copies replace the old ones · saved back to disk";
  else if (t < 9.8) note = "two rows change on another phone · Realtime";
  else if (t < 11.4) note = `${DEBOUNCE_MS} ms timer · the second change restarts it`;
  else if (t < 13.2) note = "one refresh for both changes";
  else note = "opens in one frame · works offline · one refresh per burst";

  return { t, beads, trays, tiles, phone, knob, lock, row, timer, bell, refreshes, note };
}

// The whole machine, as a pure function of time. The stations are the backend's: the phone calls
// Supabase's REST API, which is the database's own door, so every call is a SQL function running
// under row-level security (0002_security.sql) and the functions in supabase/migrations decide
// what the caller may do and see; inserts reach the phones allowed to see them over Realtime
// (the supabase_realtime publication, RealtimeHub.swift); pg_cron runs run_hit_scheduler every
// 5 minutes, resend_unpushed every 10 and purge_old_reports nightly (0008_scheduler.sql and
// later); the four Deno Edge Functions in supabase/functions are send-push (to APNs),
// delete-account, apple-token-exchange and report-email.

export const LOOP = 12;
export const BOOTHS = ["send-push", "delete-account", "apple-token-exchange", "report-email"];
export const SCHEDULES = ["reminders every 5 min", "push retries every 10 min", "cleanup nightly"];

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (a, b, t) => { const x = clamp01((t - a) / (b - a)); return x * x * (3 - 2 * x); };
const along = (t, t0, t1) => (t >= t0 && t <= t1 ? smooth(t0, t1, t) : null);

export function storyAt(time) {
  const t = ((time % LOOP) + LOOP) % LOOP;
  const beads = { toDoor: null, toCabinet: null, toBoard: null, backToCabinet: null, backToDoor: null, backToPhone: null, cron: null, toBooths: null, toMast: null, air: null };
  let phone = 0, gate = 0, gears = 0, rows = 0, bell = 0, clock = 0, boothGear = 0, mast = 0, away = 0, note = "";

  // 1. A call: phone → API door → the database. The functions run while the gears turn.
  phone = t >= 0.6 ? 1 : 0;
  beads.toDoor = along(t, 0.8, 1.8);
  gate = smooth(1.6, 2.0, t) - smooth(2.8, 3.2, t);
  beads.toCabinet = along(t, 2.0, 2.6);
  if (t >= 2.6 && t < 4.4) gears = (t - 2.6) * 1.4; else if (t >= 4.4) gears = 1.8 * 1.4;
  if (t >= 3.4) rows = 1;

  // 2. The insert is published: Realtime rings, and the change runs back out to the phone.
  beads.toBoard = along(t, 4.4, 5.0);
  bell = t >= 5.0 && t < 5.8 ? 1 : 0;
  beads.backToCabinet = along(t, 5.2, 5.6);
  beads.backToDoor = along(t, 5.6, 6.2);
  beads.backToPhone = along(t, 6.2, 6.6);

  // 3. The clock: pg_cron calls a function on its own, and the gears turn again.
  clock = smooth(6.4, 7.6, t);
  beads.cron = along(t, 7.4, 8.0);
  if (t >= 8.0 && t < 8.8) gears += (t - 8.0) * 1.4; else if (t >= 8.8) gears += 0.8 * 1.4;
  if (t >= 8.4) rows = 2;

  // 4. A push: the database calls the send-push function, which hands it to APNs, which wakes a closed phone.
  beads.toBooths = along(t, 8.6, 9.4);
  if (t >= 9.4 && t < 10.2) boothGear = (t - 9.4) * 2; else if (t >= 10.2) boothGear = 1.6;
  beads.toMast = along(t, 9.6, 10.2);
  mast = t >= 10.2 && t < 10.9 ? 1 : 0;
  beads.air = along(t, 10.4, 11.0);
  away = t >= 11.0 ? 1 : 0;

  if (t < 0.8) note = "one app · one door · one database";
  else if (t < 2.0) note = "one door into the database · every call is a SQL function";
  else if (t < 2.6) note = "row-level security · the database knows who is asking";
  else if (t < 4.4) note = "create_hit · send_message · respond_to_request · get_me";
  else if (t < 6.6) note = "Realtime · every phone allowed to see the row hears it";
  else if (t < 8.8) note = "pg_cron · reminders every 5 min · push retries · cleanup";
  else if (t < 10.4) note = "Edge Functions · push · deletion · Apple sign-in · reports";
  else if (t < 11.0) note = "send-push → APNs · a closed phone still hears";
  else note = "one door · the database decides · the rest runs itself";

  return { t, beads, phone, gate, gears, rows, bell, clock, boothGear, mast, away, note };
}

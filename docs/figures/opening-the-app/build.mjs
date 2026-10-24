// Opening the app: why it paints in one frame, and why a burst of changes is one refresh.
//
// The phone wakes and a bead runs to the keychain, whose knob turns a quarter when the session
// tokens check out. A rack of four trays is the snapshot cache: each tray slides out and lights
// its tile on the tab board at once, before anything has crossed the network. Then a bead goes to
// the database and comes back with fresh copies, and the tiles swap to them. Another phone
// changes two rows; two notices ring the bell on the board, the 400 ms timer fills and restarts,
// and one refresh goes out for both.
//
//   node docs/figures/opening-the-app/build.mjs [--light] [--audit]

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { kitScript } from "../kit/inline.mjs";
import { k, scene, phone, platter, gear, gearTeeth, routeTable } from "../kit/parts.mjs";
import * as M from "./model.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const theme = process.argv.includes("--light") ? "light" : "dark";

const WIDTH = 640;
const HEIGHT = 380;

const PLATE = { x: -214, y: -58, w: 404, d: 116, r: 8 };
const PHONE = [-186, -10];
const SAFE = { x: -156, y: -22, w: 22, d: 20, r: 2 };
const SAFE_H = 14;
const KNOB = [SAFE.x + 11, SAFE.y + 10];
const RACK = { x: -118, y: -34, w: 38, d: 20 };          // the snapshot rack: posts, shelves, trays
const SHELF_Z = [5, 12, 19, 26];   // tray floors; the first sits on the rack's base
const TRAY_SLIDE = 12;
const BOARD = { x: -62, y: -30, w: 34, d: 18, r: 2 };
const BOARD_H = 6;
const TILE_XS = [0, 1, 2, 3].map((i) => BOARD.x + 6 + i * 7.3);
const TIMER = [BOARD.x + 27, BOARD.y + 13];
const CABINET = { x: 6, y: -32, w: 64, d: 40, r: 3 };
const CABINET_H = 14;
const PLATTER = [CABINET.x + 18, CABINET.y + 12];
const BELL = [CABINET.x + 46, CABINET.y + 12];
const OTHER = [150, 2];
const PIPE_Z = 2.8;

const P = k.fitProjection(
  [...k.boxCorners(PLATE, -17, 0), [PHONE[0], PHONE[1], 36], [OTHER[0], OTHER[1], 36], [RACK.x, RACK.y, 35], [BELL[0], BELL[1], CABINET_H + 14]],
  WIDTH,
  HEIGHT,
  { pad: 26, azimuth: 48, elevation: 32 },
);
const sc = scene(P);
const { at, S, L, D } = sc;

sc.plate(PLATE, {
  engraving: [
    sc.label("PHONE", PHONE[0] + 2, 16),
    sc.label("KEYCHAIN", SAFE.x + SAFE.w / 2, SAFE.y + SAFE.d + 10),
    sc.label("SNAPSHOTS · ON DISK", RACK.x + RACK.w / 2, RACK.y + RACK.d + 22),
    sc.label("TABS", BOARD.x + BOARD.w / 2, BOARD.y + BOARD.d + 10),
    sc.label("POSTGRES · REALTIME", CABINET.x + CABINET.w / 2, CABINET.y + CABINET.d + 10),
    sc.label("ANOTHER PHONE", OTHER[0], OTHER[1] + 20),
  ].join(""),
});

// MARK: - Phone and keychain

phone(sc, "phone", PHONE);
sc.slab("safe", SAFE, 0, SAFE_H, { tone: "hi", crease: "lo", bevel: 0.8, extra: L(k.sideSeam(SAFE, 4, P, 4), { tone: "faint" }) + D(k.corners(SAFE, 3).map(([x, y]) => at([x, y, SAFE_H])), { size: 0.45 }) });
const KNOB_GEAR = gear(sc, "safe.knob", KNOB, SAFE_H, { r: 4.5, h: 3, teeth: 8 });
sc.cyl("safe.lamp", SAFE.x + 4, SAFE.y + 4, 1.6, SAFE_H, 2, { tone: "hi", crease: "lo", steps: 14, wrap: (s) => `<g data-lamp="lock">${s}</g>` });

// MARK: - The snapshot rack

sc.slab("rack.base", { x: RACK.x - 1.6, y: RACK.y - 1.6, w: RACK.w + 3.2, d: RACK.d + 3.2, r: 1.2 }, 0, SHELF_Z[0], { bevel: 0.6 });
[[RACK.x, RACK.y, "bl"], [RACK.x + RACK.w, RACK.y, "br"], [RACK.x, RACK.y + RACK.d, "fl"], [RACK.x + RACK.w, RACK.y + RACK.d, "fr"]].forEach(([cx, cy, tag]) => {
  sc.cyl(`rack.post.${tag}`, cx, cy, 1.4, SHELF_Z[0], 27, { steps: 12, bias: cy > RACK.y ? 0.3 : 0 });
});
SHELF_Z.forEach((z, i) => {
  if (i > 0) sc.slab(`rack.shelf${i}`, { x: RACK.x + 0.7, y: RACK.y + 0.7, w: RACK.w - 1.4, d: RACK.d - 1.4, r: 0.4 }, z - 1.5, 1.5, { steps: 3, bevel: 0.3 });   // let into the posts at the corners
});
sc.slab("rack.cap", { x: RACK.x - 1.6, y: RACK.y - 1.6, w: RACK.w + 3.2, d: RACK.d + 3.2, r: 1.2 }, SHELF_Z[0] + 27, 1.5, { steps: 3, bevel: 0.3 });
M.SNAPSHOTS.forEach((name, i) => {
  const z = SHELF_Z[i];
  const tray = { x: RACK.x + 3, y: RACK.y + 1, w: RACK.w - 6, d: RACK.d - 2, r: 1 };
  const card = L(k.planOutline({ x: tray.x + 4, y: tray.y + 4, w: tray.w - 8, d: tray.d - 8, r: 1 }, z + 4, P, 3), { tone: "lo" })
    + L(k.lineOnTop([tray.x + 7, tray.y + 8], [tray.x + tray.w - 9, tray.y + 8], z + 4, P), { tone: "faint", free: true })
    + L(k.lineOnTop([tray.x + 7, tray.y + 11], [tray.x + tray.w - 12, tray.y + 11], z + 4, P), { tone: "faint", free: true });
  const pull = S(k.cylinder(tray.x + tray.w / 2, tray.y + tray.d + 0.8, 1.2, z + 1.5, 1.4, P, 12), { tone: "mid" });
  sc.slab(`tray.${name}`, tray, z, 4, { tone: "hi", crease: "lo", steps: 3, bevel: 0.3, bias: 0.4, extra: card + pull, wrap: (s) => `<g data-tray="${i}">${s}</g>` });
});

// MARK: - The tab board, its tiles and the debounce timer

sc.slab("board", BOARD, 0, BOARD_H, { extra: L(k.planOutline(k.insetPlan(BOARD, 2), BOARD_H, P, 4), { tone: "faint" }) + D(k.corners(BOARD, 3).map(([x, y]) => at([x, y, BOARD_H])), { size: 0.45 }) });
TILE_XS.forEach((x, i) => {
  sc.slab(`tile${i}`, { x: x - 2.6, y: BOARD.y + 3.5, w: 5.2, d: 5.2, r: 0.8 }, BOARD_H, 1.2, { tone: "hi", crease: "lo", steps: 3, bias: 0.3, wrap: (s) => `<g data-tile="${i}">${s}</g>` });
});
sc.cyl("timer", TIMER[0], TIMER[1], 3.6, BOARD_H, 1.6, {
  tone: "hi", crease: "lo", steps: 28, bevel: 0.3, bias: 0.3,
  extra: (() => { const t = k.radialTicks(TIMER[0], TIMER[1], 2.9, 8, 4, BOARD_H + 1.6, [0.6, 1.1], P); return L(t.minor, { tone: "lo" }) + L(t.major, { tone: "mid" }) + L(k.ring(TIMER[0], TIMER[1], 0.6, BOARD_H + 1.6, P, 8), { tone: "mid" }); })(),
});
sc.cyl("board.bell.post", BOARD.x + 6, BOARD.y + 13, 1.2, BOARD_H, 5, { steps: 12, bias: 0.2 });
sc.cyl("board.bell", BOARD.x + 6, BOARD.y + 13, 3.2, BOARD_H + 5, 2.8, { tone: "hi", crease: "lo", steps: 20, bevel: 0.4, bias: 0.4, wrap: (s) => `<g data-lamp="bell">${s}</g>` });

// MARK: - The database

sc.slab("cabinet", CABINET, 0, CABINET_H, {
  tone: "hi", crease: "lo", steps: 5, bevel: 0.9,
  extra: L(k.planOutline(k.insetPlan(CABINET, 3), CABINET_H, P, 5), { tone: "faint" }) + D(k.corners(CABINET, 4).map(([x, y]) => at([x, y, CABINET_H])), { size: 0.45 }),
});
platter(sc, "platter", PLATTER, CABINET_H, { r: 7, h: 10, rows: 3 });
sc.cyl("cabinet.bell.post", BELL[0], BELL[1], 1.4, CABINET_H, 7, { steps: 12 });
sc.cyl("cabinet.bell", BELL[0], BELL[1], 4.2, CABINET_H + 7, 3.4, { tone: "hi", crease: "lo", steps: 24, bevel: 0.4, bias: 0.3, extra: L(k.sideArc(BELL[0], BELL[1], 4.2, CABINET_H + 8.2, P, 16), { tone: "faint" }) });

phone(sc, "other", OTHER);

// MARK: - Pipes

const ROUTES = {
  tokens: sc.pipe("pipe.tokens", [[PHONE[0] + 12, PHONE[1], PIPE_Z], [SAFE.x, PHONE[1], PIPE_Z]], 1.6, { bend: 4 }),
  disk: sc.pipe("pipe.disk", [[SAFE.x + SAFE.w, SAFE.y + 10, PIPE_Z], [RACK.x - 13, SAFE.y + 10, PIPE_Z], [RACK.x - 13, RACK.y + 5, PIPE_Z], [RACK.x - 1.6, RACK.y + 5, PIPE_Z]], 1.6, { bend: 4 }),
  board: sc.pipe("pipe.board", [[RACK.x + RACK.w + 1.6, RACK.y + 10, PIPE_Z], [BOARD.x, RACK.y + 10, PIPE_Z]], 1.6, { bend: 4 }),
  net: sc.pipe("pipe.net", [[BOARD.x + BOARD.w, BOARD.y + 9, PIPE_Z], [CABINET.x, BOARD.y + 9, PIPE_Z]], 1.6, { bend: 4 }),
  other: sc.pipe("pipe.other", [[OTHER[0] - 12, OTHER[1], PIPE_Z], [CABINET.x + CABINET.w, OTHER[1], PIPE_Z]], 1.6, { bend: 4 }),
};
const SCREEN_ROUTES = Object.fromEntries(Object.entries(ROUTES).map(([n, r]) => [n, routeTable(r, P)]));

// MARK: - Page

const start = M.storyAt(0);
const beadNames = Object.keys(start.beads);
const beads = beadNames.map((n) => `<g class="pulse" data-pulse="${n}" opacity="0"><circle class="pulse-glow" r="5"/><circle class="pulse-core" r="2"/></g>`).join("");
const timerHand = (share) => {
  const a = share * Math.PI * 2;
  return k.lineOnTop([TIMER[0], TIMER[1]], [TIMER[0] + Math.sin(a) * 2.6, TIMER[1] - Math.cos(a) * 2.6], BOARD_H + 1.8, P);
};
const svgBody = sc.body() + `<path data-part="timer-hand" class="iso-line" data-tone="lit" data-free="start" d="${timerHand(0)}" style="stroke-width:0.9"/>` + beads;
const svg = k.figureSvg({
  width: WIDTH,
  height: HEIGHT,
  label:
    "A bench joined by pipes: a phone, a keychain safe with a knob, a rack of four trays, a tab board with four tiles and a timer, a database cabinet with a platter and a bell, and another phone. Beads run from the phone through the keychain to the rack; trays slide out and tiles light; a bead crosses to the database and back; the other phone rings the bell twice and one refresh goes out.",
  body: [svgBody],
});

const modelScript = readFileSync(join(HERE, "model.mjs"), "utf8").replace(/^export /gm, "");
const gearSource = gearTeeth.toString().replace("k.lineOnTop", "lineOnTop");

const live = `
const P = ${JSON.stringify(P)};
const ROUTES = ${JSON.stringify(SCREEN_ROUTES)};
const KNOB = ${JSON.stringify(KNOB_GEAR)}, TIMER = ${JSON.stringify(TIMER)}, BOARD_H = ${BOARD_H}, TRAY_SLIDE = ${TRAY_SLIDE};
const stage = document.querySelector(".iso-stage");
const svg = stage.querySelector("svg");
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");
const q = (s) => svg.querySelector(s);
const beads = Object.fromEntries(${JSON.stringify(beadNames)}.map((n) => [n, q('[data-pulse="' + n + '"]')]));
const trayEls = [0, 1, 2, 3].map((i) => q('[data-tray="' + i + '"]'));
const tileEls = [0, 1, 2, 3].map((i) => q('[data-tile="' + i + '"]'));
const rowEls = [0, 1, 2].map((i) => q('[data-row="' + i + '"] .iso-line'));
const knobEl = q('[data-gear="safe.knob"]'), lockEl = q('[data-lamp="lock"]'), bellEl = q('[data-lamp="bell"]'), hand = q('[data-part="timer-hand"]');
const screens = { phone: q('[data-screen="phone"]'), other: q('[data-screen="other"]') };
const gearTeeth = ${gearSource};
const timerHand = ${timerHand.toString().replace("k.lineOnTop", "lineOnTop")};
const tables = Object.fromEntries(Object.entries(ROUTES).map(([name, pts]) => {
  const lens = [0];
  for (let i = 1; i < pts.length; i++) lens.push(lens[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  return [name, { pts, lens, total: lens[lens.length - 1] }];
}));
const pointAt = (name, share) => {
  const { pts, lens, total } = tables[name];
  const d = share * total;
  let i = 1;
  while (i < lens.length - 1 && lens[i] < d) i++;
  const f = (d - lens[i - 1]) / Math.max(1e-6, lens[i] - lens[i - 1]);
  return [pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f, pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f];
};
const place = (el, name, share, reverse = false) => {
  if (share === null) { el.setAttribute("opacity", "0"); return; }
  const [x, y] = pointAt(name, reverse ? 1 - share : share);
  el.setAttribute("transform", "translate(" + x.toFixed(1) + " " + y.toFixed(1) + ")"); el.setAttribute("opacity", "1");
};
let clock = 0, playing = !still.matches, frame = 0, last = 0, visible = false, idleTimer = 0, shown = "";
function draw() {
  const s = storyAt(clock);
  place(beads.tokens, "tokens", s.beads.tokens);
  place(beads.disk, "disk", s.beads.disk);
  place(beads.net, "net", s.beads.net);
  place(beads.netBack, "net", s.beads.netBack, true);
  place(beads.other, "other", s.beads.other);
  place(beads.notice1, "net", s.beads.notice1, true);
  place(beads.notice2, "net", s.beads.notice2, true);
  place(beads.refresh, "net", s.beads.refresh);
  place(beads.refreshBack, "net", s.beads.refreshBack, true);
  s.trays.forEach((out, i) => trayEls[i].setAttribute("transform", translateAlong(P, [0, out * TRAY_SLIDE, 0])));
  s.tiles.forEach((state, i) => { tileEls[i].setAttribute("data-state", String(state)); });
  rowEls.forEach((el, i) => el.setAttribute("data-tone", s.row && i === 0 ? "green" : "faint"));
  knobEl.setAttribute("d", gearTeeth(KNOB.x, KNOB.y, KNOB.r, KNOB.teeth, KNOB.z, s.knob, P));
  lockEl.toggleAttribute("data-on", s.lock === 1);
  bellEl.toggleAttribute("data-on", s.bell === 1);
  hand.setAttribute("d", timerHand(s.timer));
  screens.phone.toggleAttribute("data-on", s.phone === 1);
  screens.other.toggleAttribute("data-on", s.beads.other !== null || s.t >= 9.2);
  if (shown !== s.note) { shown = s.note; readout.textContent = s.note; stage.setAttribute("aria-valuetext", s.note); }
  stage.setAttribute("aria-valuenow", String(Math.round(clock)));
}
function tick(now) {
  const dt = last ? Math.min((now - last) / 1000, 1 / 30) : 1 / 60;
  last = now;
  if (playing) clock = (clock + dt) % LOOP;
  draw();
  frame = visible && playing ? requestAnimationFrame(tick) : 0;
}
const run = () => { if (!frame && visible) { last = 0; frame = requestAnimationFrame(tick); } };
const scrub = (to) => {
  playing = false; clock = Math.min(LOOP - 0.001, Math.max(0, to)); draw();
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { if (!still.matches) { playing = true; run(); } }, 3600);
};
new IntersectionObserver((entries) => { visible = entries[entries.length - 1].isIntersecting; if (visible) run(); }, { rootMargin: "120px 0px" }).observe(stage);
stage.addEventListener("pointermove", (event) => { const box = svg.getBoundingClientRect(); scrub(((event.clientX - box.left) / box.width) * LOOP); });
stage.addEventListener("keydown", (event) => {
  if (event.key === "ArrowRight" || event.key === "ArrowUp") scrub(clock + (event.shiftKey ? 2 : 0.5));
  else if (event.key === "ArrowLeft" || event.key === "ArrowDown") scrub(clock - (event.shiftKey ? 2 : 0.5));
  else if (event.key === "Home") scrub(0);
  else if (event.key === "End") scrub(LOOP - 0.001);
  else if (event.key === " " || event.key === "Enter") { clearTimeout(idleTimer); playing = !playing; if (playing) run(); }
  else return;
  event.preventDefault();
});
window.__story = { seek: (t) => { playing = false; clearTimeout(idleTimer); clock = t; draw(); }, loop: LOOP };
draw();
`;

const css = `<style>
.pulse-core{fill:var(--anatomy-lit)}
.pulse-glow{fill:var(--anatomy-lit);opacity:.22}
.screen{fill:var(--anatomy-paper)}
[data-screen][data-on] .screen{fill:var(--anatomy-green);opacity:.75}
[data-tile][data-state="1"] .iso-top{fill:var(--anatomy-green);opacity:.45}
[data-tile][data-state="2"] .iso-top{fill:var(--anatomy-green)}
[data-tile][data-state="2"] .iso-edge{stroke:var(--anatomy-green)}
[data-lamp][data-on] .iso-top{fill:var(--anatomy-green)}
[data-lamp][data-on] .iso-edge{stroke:var(--anatomy-green)}
</style>`;

const body = k.plateHtml({
  fig: "Fig 4",
  title: "Opening the app",
  hint: "Hover to scrub · space plays",
  readout: start.note,
  keys: [
    { mark: "lit", label: "A request or a change, on its way" },
    { mark: "raised", label: "Trays: the last copy of each tab, kept on the phone" },
    { mark: "green", label: "A tab painted (pale: from disk, full: fresh), a lamp lit" },
  ],
  caption:
    "Opening the app. The keychain's session tokens are checked, then every tab paints from the copy it kept on disk, before the network has answered; the fresh copies arrive and replace them, and are saved back for next time. When rows change on another phone, each change starts a 400 ms timer and a burst of changes becomes one refresh. Offline, the app keeps what the device has.",
  body: `${css}<div class="iso-stage" tabindex="0" role="slider" aria-label="Opening the app: a story in ${M.LOOP} seconds. Arrow keys step through it, space plays and pauses" aria-valuemin="0" aria-valuemax="${M.LOOP}" aria-valuenow="0">${svg}</div>`,
});

const end = M.storyAt(M.LOOP - 0.01);
if (end.tiles.some((v) => v !== 2) || end.refreshes !== 1 || end.lock !== 1) {
  throw new Error(`The story does not end with every tab fresh, one refresh and the session checked: ${JSON.stringify(end)}`);
}

const file = theme === "light" ? "index-light.html" : "index.html";
writeFileSync(join(HERE, file), k.pageHtml({ title: "Opening the app", theme, body, script: kitScript() + modelScript + live }));
console.log("wrote", file, `${sc.R.items.length} items`);
sc.audit({});

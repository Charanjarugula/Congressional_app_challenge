// The whole machine: every station the app talks to, on one bench, and one call walking through.
//
// A bead leaves the phone, passes the API door (the gate lifts), and enters the database cabinet
// behind its row-level-security fence; the gear train turns while the functions run and a row
// lights on the platter. The insert rings the Realtime bell and a bead runs back out to the phone.
// The pg_cron clock sweeps and sends a bead of its own into the cabinet. Then the database calls
// the send-push booth, whose gear turns, and a bead climbs to the APNs mast and crosses the air to
// a phone that is closed.
//
//   node docs/figures/whole-machine/build.mjs [--light] [--audit]

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { kitScript } from "../kit/inline.mjs";
import { k, scene, phone, platter, gear, booth, gearTeeth, routeTable } from "../kit/parts.mjs";
import * as M from "./model.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const theme = process.argv.includes("--light") ? "light" : "dark";

const WIDTH = 640;
const HEIGHT = 380;

const PLATE = { x: -232, y: -64, w: 464, d: 128, r: 8 };
const PHONE = [-206, 0];
const ARCH = [-170, 0];                                   // the API door
const CABINET = { x: -148, y: -32, w: 74, d: 48, r: 3 };
const CABINET_H = 16;
const FENCE_X = CABINET.x + 5;                            // the row-level-security fence, along the door side
const FENCE_YS = [-24, -16, -8, 0, 8];
const PLATTER = [CABINET.x + 54, CABINET.y + 14];
const GEARS = [{ at: [CABINET.x + 24, CABINET.y + 32], r: 6.5 }, { at: [CABINET.x + 34.6, CABINET.y + 32], r: 4.5 }];   // meshing: centres r1 + r2 − 0.4 apart
const BOARD = { x: -60, y: -28, w: 30, d: 22, r: 2 };    // Realtime
const BOARD_H = 7;
const BELL = [BOARD.x + 10, BOARD.y + 11];
const PLINTH = { x: -30, y: -50, w: 22, d: 22, r: 2 };   // pg_cron
const CLOCK = [PLINTH.x + 11, PLINTH.y + 11];
const BOOTH_XS = [0, 34, 68, 102];
const BOOTH_PLAN = (x) => ({ x, y: -9, w: 22, d: 18, r: 2 });
const MAST_FOOT = { x: 3, y: -60, w: 16, d: 16, r: 2 };
const MAST = [MAST_FOOT.x + 8, MAST_FOOT.y + 8];
const MAST_H = 42;
const AWAY = [184, 8];
const PIPE_Z = 2.8;

const P = k.fitProjection(
  [...k.boxCorners(PLATE, -17, 0), [PHONE[0], PHONE[1], 36], [AWAY[0], AWAY[1], 36], [MAST[0], MAST[1], MAST_H + 6], [CLOCK[0], CLOCK[1], 20]],
  WIDTH,
  HEIGHT,
  { pad: 26, azimuth: 48, elevation: 32 },
);
const sc = scene(P);
const { at, S, L, D } = sc;

sc.plate(PLATE, {
  engraving: [
    sc.label("PHONE", PHONE[0] + 2, 26),
    sc.label("API", ARCH[0], 20),
    sc.label("POSTGRES · RLS", CABINET.x + CABINET.w / 2, CABINET.y + CABINET.d + 10),
    sc.label("REALTIME", BOARD.x + BOARD.w / 2, BOARD.y + BOARD.d + 10),
    sc.label("PG_CRON", PLINTH.x + PLINTH.w + 8, PLINTH.y + 14, { size: 3.2 }),
    sc.label("APNS", MAST_FOOT.x + MAST_FOOT.w + 9, MAST_FOOT.y + 8),
    ...M.BOOTHS.map((name, i) => sc.label(name.toUpperCase(), BOOTH_XS[i] + 11, 20, { size: 2.6 })),
    sc.label("A PHONE THAT IS CLOSED", AWAY[0], AWAY[1] + 26),
  ].join(""),
});

// MARK: - Phone and the API door

phone(sc, "phone", PHONE);
for (const dy of [-9, 9]) sc.slab(`arch.post${dy > 0 ? "F" : "B"}`, { x: ARCH[0] - 2, y: ARCH[1] + dy - 2, w: 4, d: 4, r: 1 }, 0, 14, { steps: 3, bevel: 0.4 });
sc.slab("arch.lintel", { x: ARCH[0] - 2.5, y: ARCH[1] - 11, w: 5, d: 22, r: 1 }, 14, 3, { steps: 3, bevel: 0.4, extra: D([at([ARCH[0], ARCH[1] - 9, 17]), at([ARCH[0], ARCH[1] + 9, 17])], { size: 0.45 }) });
sc.slab("arch.gate", { x: ARCH[0] - 1, y: ARCH[1] - 7, w: 2, d: 14, r: 0.6 }, 0, 9, { tone: "hi", crease: "lo", steps: 3, bevel: 0.3, bias: 0.2, wrap: (s) => `<g data-part="gate">${s}</g>` });

// MARK: - The database: cabinet, fence, gear train, platter

sc.slab("cabinet", CABINET, 0, CABINET_H, {
  tone: "hi", crease: "lo", steps: 5, bevel: 0.9,
  extra: L(k.planOutline(k.insetPlan(CABINET, 3), CABINET_H, P, 5), { tone: "faint" }) + D(k.corners(CABINET, 4).map(([x, y]) => at([x, y, CABINET_H])), { size: 0.45 }),
});
FENCE_YS.forEach((y, i) => sc.cyl(`fence.post${i}`, FENCE_X, y, 1, CABINET_H, 6, { steps: 10 }));
sc.slab("fence.rail", { x: FENCE_X - 1.1, y: FENCE_YS[0] - 1.1, w: 2.2, d: FENCE_YS[FENCE_YS.length - 1] - FENCE_YS[0] + 2.2, r: 0.6 }, CABINET_H + 5.7, 1.2, { steps: 3, bevel: 0.3 });
const GEAR_PARTS = GEARS.map((g, i) => gear(sc, `gear${i}`, g.at, CABINET_H, { r: g.r, h: 3, teeth: Math.round(g.r * 2) }));
platter(sc, "platter", PLATTER, CABINET_H, { r: 8, h: 11, rows: 3 });

// MARK: - Realtime, pg_cron, the booths and the mast

sc.slab("board", BOARD, 0, BOARD_H, { extra: L(k.planOutline(k.insetPlan(BOARD, 2), BOARD_H, P, 4), { tone: "faint" }) + D(k.corners(BOARD, 3).map(([x, y]) => at([x, y, BOARD_H])), { size: 0.45 }) });
sc.cyl("board.bell.post", BELL[0], BELL[1], 1.4, BOARD_H, 6, { steps: 12 });
sc.cyl("board.bell", BELL[0], BELL[1], 4, BOARD_H + 6, 3.2, { tone: "hi", crease: "lo", steps: 24, bevel: 0.4, bias: 0.3, extra: L(k.sideArc(BELL[0], BELL[1], 4, BOARD_H + 7.2, P, 16), { tone: "faint" }), wrap: (s) => `<g data-lamp="bell">${s}</g>` });
[0, 1, 2].forEach((i) => sc.slab(`board.socket${i}`, { x: BOARD.x + 19, y: BOARD.y + 3.5 + i * 5.6, w: 6, d: 4, r: 0.8 }, BOARD_H, 1, { tone: "hi", crease: "lo", steps: 3, bias: 0.2 }));

sc.slab("plinth", PLINTH, 0, 5, { extra: D(k.corners(PLINTH, 3).map(([x, y]) => at([x, y, 5])), { size: 0.45 }) });
sc.cyl("clock", CLOCK[0], CLOCK[1], 7.5, 5, 9, {
  tone: "hi", crease: "lo", steps: 32, bevel: 0.5,
  extra: (() => { const t = k.radialTicks(CLOCK[0], CLOCK[1], 6.4, 12, 3, 14, [0.8, 1.6], P); return L(t.minor, { tone: "lo" }) + L(t.major, { tone: "mid" }) + L(k.ring(CLOCK[0], CLOCK[1], 0.7, 14, P, 8), { tone: "mid" }); })(),
});

const BOOTH_GEARS = M.BOOTHS.map((name, i) => booth(sc, `booth.${name}`, BOOTH_PLAN(BOOTH_XS[i]), { h: 12 }));

sc.slab("mast.foot", MAST_FOOT, 0, 5, { bevel: 0.5 });
sc.cyl("mast.pole", MAST[0], MAST[1], 1.5, 5, MAST_H - 5, { steps: 12, extra: L([0.35, 0.6, 0.85].map((s) => k.sideArc(MAST[0], MAST[1], 1.5, 5 + (MAST_H - 5) * s, P, 12)).join(""), { tone: "faint" }) });
sc.cyl("mast.lamp", MAST[0], MAST[1], 3.2, MAST_H, 2.6, { tone: "hi", crease: "lo", steps: 20, bevel: 0.4, wrap: (s) => `<g data-lamp="mast">${s}</g>` });

phone(sc, "away", AWAY);

// MARK: - Pipes

const ROUTES = {
  toDoor: sc.pipe("pipe.toDoor", [[PHONE[0] + 12, PHONE[1], PIPE_Z], [ARCH[0] - 1, PHONE[1], PIPE_Z]], 1.6),
  toCabinet: sc.pipe("pipe.toCabinet", [[ARCH[0] + 1, ARCH[1], PIPE_Z], [CABINET.x, ARCH[1], PIPE_Z]], 1.6),
  toBoard: sc.pipe("pipe.toBoard", [[CABINET.x + CABINET.w, -16, PIPE_Z], [BOARD.x, -16, PIPE_Z]], 1.6),
  cron: sc.pipe("pipe.cron", [[PLINTH.x, PLINTH.y + 11, PIPE_Z], [CABINET.x + CABINET.w - 14, PLINTH.y + 11, PIPE_Z], [CABINET.x + CABINET.w - 14, CABINET.y, PIPE_Z]], 1.6, { bend: 5 }),
  toBooths: sc.pipe("pipe.toBooths", [[CABINET.x + CABINET.w, 4, PIPE_Z], [BOOTH_XS[0], 4, PIPE_Z]], 1.6),
  bus1: sc.pipe("pipe.bus1", [[BOOTH_XS[0] + 22, 0, PIPE_Z], [BOOTH_XS[1], 0, PIPE_Z]], 1.6),
  bus2: sc.pipe("pipe.bus2", [[BOOTH_XS[1] + 22, 0, PIPE_Z], [BOOTH_XS[2], 0, PIPE_Z]], 1.6),
  bus3: sc.pipe("pipe.bus3", [[BOOTH_XS[2] + 22, 0, PIPE_Z], [BOOTH_XS[3], 0, PIPE_Z]], 1.6),
  toMast: sc.pipe("pipe.toMast", [[MAST[0], -9, PIPE_Z], [MAST[0], MAST_FOOT.y + MAST_FOOT.d, PIPE_Z]], 1.6),
};
const SCREEN_ROUTES = Object.fromEntries(Object.entries(ROUTES).map(([n, r]) => [n, routeTable(r, P)]));
const AIR = [at([MAST[0], MAST[1], MAST_H + 2.6]), at([AWAY[0], AWAY[1], 30])];   // the push, through the air

// MARK: - Page

const start = M.storyAt(0);
const beadNames = Object.keys(start.beads);
const beads = beadNames.map((n) => `<g class="pulse" data-pulse="${n}" opacity="0"><circle class="pulse-glow" r="5"/><circle class="pulse-core" r="2"/></g>`).join("");
const clockHand = (share) => {
  const a = share * Math.PI * 2;
  return k.lineOnTop([CLOCK[0], CLOCK[1]], [CLOCK[0] + Math.sin(a) * 5.4, CLOCK[1] - Math.cos(a) * 5.4], 14.2, P);
};
const svgBody = sc.body() + `<path data-part="clock-hand" class="iso-line" data-tone="lit" data-free="start" d="${clockHand(0)}" style="stroke-width:0.9"/>` + beads;
const svg = k.figureSvg({
  width: WIDTH,
  height: HEIGHT,
  label:
    "A long bench joined by pipes: a phone, an API door with a gate, a database cabinet with a fence, two gears and a platter, a Realtime board with a bell, a pg_cron clock, four Edge Function booths with gears, an APNs mast, and a phone that is closed. A bead walks from the phone through the door into the cabinet, rings the bell and returns; the clock sends a bead of its own; a bead reaches the send-push booth, climbs the mast and crosses to the closed phone.",
  body: [svgBody],
});

const modelScript = readFileSync(join(HERE, "model.mjs"), "utf8").replace(/^export /gm, "");
const gearSource = gearTeeth.toString().replace("k.lineOnTop", "lineOnTop");

const live = `
const P = ${JSON.stringify(P)};
const ROUTES = ${JSON.stringify(SCREEN_ROUTES)};
const GEARS = ${JSON.stringify(GEAR_PARTS)}, BOOTH_GEARS = ${JSON.stringify(BOOTH_GEARS)}, CLOCK = ${JSON.stringify(CLOCK)}, AIR = ${JSON.stringify(AIR)};
const stage = document.querySelector(".iso-stage");
const svg = stage.querySelector("svg");
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");
const q = (s) => svg.querySelector(s);
const beads = Object.fromEntries(${JSON.stringify(beadNames)}.map((n) => [n, q('[data-pulse="' + n + '"]')]));
const gearEls = GEARS.map((_, i) => q('[data-gear="gear' + i + '"]'));
const boothGearEls = ${JSON.stringify(M.BOOTHS)}.map((n) => q('[data-gear="booth.' + n + '.gear"]'));
const rowEls = [0, 1, 2].map((i) => q('[data-row="' + i + '"] .iso-line'));
const gateEl = q('[data-part="gate"]'), bellEl = q('[data-lamp="bell"]'), mastEl = q('[data-lamp="mast"]'), hand = q('[data-part="clock-hand"]');
const screens = { phone: q('[data-screen="phone"]'), away: q('[data-screen="away"]') };
const gearTeeth = ${gearSource};
const clockHand = ${clockHand.toString().replace("k.lineOnTop", "lineOnTop")};
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
const show = (el, xy) => { el.setAttribute("transform", "translate(" + xy[0].toFixed(1) + " " + xy[1].toFixed(1) + ")"); el.setAttribute("opacity", "1"); };
const place = (el, name, share, reverse = false) => {
  if (share === null) { el.setAttribute("opacity", "0"); return; }
  show(el, pointAt(name, reverse ? 1 - share : share));
};
// The booth bus is one run of pipe through the booths: the bead's share covers all four pieces.
const BUS = ["toBooths", "bus1", "bus2", "bus3"];
const placeOnBus = (el, share) => {
  if (share === null) { el.setAttribute("opacity", "0"); return; }
  const total = BUS.reduce((sum, n) => sum + tables[n].total, 0);
  let d = share * total * (tables.toBooths.total / total);   // the push bead only reaches the first booth
  show(el, pointAt("toBooths", Math.min(1, d / tables.toBooths.total)));
};
let clock = 0, playing = !still.matches, frame = 0, last = 0, visible = false, idleTimer = 0, shown = "";
function draw() {
  const s = storyAt(clock);
  place(beads.toDoor, "toDoor", s.beads.toDoor);
  place(beads.toCabinet, "toCabinet", s.beads.toCabinet);
  place(beads.toBoard, "toBoard", s.beads.toBoard);
  place(beads.backToCabinet, "toBoard", s.beads.backToCabinet, true);
  place(beads.backToDoor, "toCabinet", s.beads.backToDoor, true);
  place(beads.backToPhone, "toDoor", s.beads.backToPhone, true);
  place(beads.cron, "cron", s.beads.cron);
  placeOnBus(beads.toBooths, s.beads.toBooths);
  place(beads.toMast, "toMast", s.beads.toMast, true);
  if (s.beads.air === null) beads.air.setAttribute("opacity", "0");
  else show(beads.air, [AIR[0][0] + (AIR[1][0] - AIR[0][0]) * s.beads.air, AIR[0][1] + (AIR[1][1] - AIR[0][1]) * s.beads.air - Math.sin(s.beads.air * Math.PI) * 18]);
  gateEl.setAttribute("transform", translateAlong(P, [0, 0, s.gate * 7]));
  gearEls.forEach((el, i) => el.setAttribute("d", gearTeeth(GEARS[i].x, GEARS[i].y, GEARS[i].r, GEARS[i].teeth, GEARS[i].z, (i === 0 ? 1 : -GEARS[0].r / GEARS[1].r) * s.gears, P)));
  boothGearEls.forEach((el, i) => { const g = BOOTH_GEARS[i]; el.setAttribute("d", gearTeeth(g.x, g.y, g.r, g.teeth, g.z, i === 0 ? s.boothGear : 0, P)); });
  rowEls.forEach((el, i) => el.setAttribute("data-tone", i < s.rows ? "green" : "faint"));
  bellEl.toggleAttribute("data-on", s.bell === 1);
  mastEl.toggleAttribute("data-on", s.mast === 1);
  hand.setAttribute("d", clockHand(s.clock));
  screens.phone.toggleAttribute("data-on", s.phone === 1);
  screens.away.toggleAttribute("data-on", s.away === 1);
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
[data-lamp][data-on] .iso-top{fill:var(--anatomy-green)}
[data-lamp][data-on] .iso-edge{stroke:var(--anatomy-green)}
</style>`;

const body = k.plateHtml({
  fig: "Fig 0",
  title: "The whole machine",
  hint: "Hover to scrub · space plays",
  readout: start.note,
  keys: [
    { mark: "lit", label: "A call, a change or a push, on its way" },
    { mark: "raised", label: "Gears turn while a function runs" },
    { mark: "green", label: "A row written, a bell rung, a screen lit" },
  ],
  caption:
    "The whole machine. The phone's every call goes through one door, the database's own API, where row-level security knows who is asking and a SQL function does the work. An insert reaches every phone allowed to see it over Realtime. pg_cron calls functions on its own clock. For the few things SQL cannot do, the database calls a Deno Edge Function: send-push hands notifications to APNs, and the others delete an account, exchange an Apple token and send a report.",
  body: `${css}<div class="iso-stage" tabindex="0" role="slider" aria-label="The whole machine: a story in ${M.LOOP} seconds. Arrow keys step through it, space plays and pauses" aria-valuemin="0" aria-valuemax="${M.LOOP}" aria-valuenow="0">${svg}</div>`,
});

const end = M.storyAt(M.LOOP - 0.01);
if (end.rows !== 2 || end.away !== 1 || end.phone !== 1) {
  throw new Error(`The story does not end with two rows written and the closed phone woken: ${JSON.stringify(end)}`);
}

const file = theme === "light" ? "index-light.html" : "index.html";
writeFileSync(join(HERE, file), k.pageHtml({ title: "The whole machine", theme, body, script: kitScript() + modelScript + live }));
console.log("wrote", file, `${sc.R.items.length} items`);
sc.audit({});

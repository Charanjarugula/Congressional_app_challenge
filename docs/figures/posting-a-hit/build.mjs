// Posting a hit: what the backend does with it, and how every player's list is built.
//
// The host's phone sends the post down a pipe, through the API door, onto the database cabinet,
// where four lift gates are create_hit's limits and the row drops onto the platter. Then the feed
// sorter runs: each viewer's card rolls up to the test station, where a distance dial swings to
// the miles between the court and their home point, a busy mask slides over a viewer whose hour
// is blocked, and a flap lifts for a friend; the card then rolls into From friends, Near you, or
// the chute of hits that viewer never sees. Two phones with Play open hear the insert and refresh
// once. Gears turn only while the function runs.
//
//   node docs/figures/posting-a-hit/build.mjs [--light] [--audit]

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
const HOST = [-186, -14];
const ARCH = [-140, -14];
const CABINET = { x: -108, y: -32, w: 86, d: 40, r: 3 };
const CABINET_H = 14;
const LANE_Y = -14;                                      // the channel across the cabinet top
const GATE_XS = M.GATE_AT.map((s) => CABINET.x + 8 + s * (CABINET.w - 16));
const PLATTER = [CABINET.x + 14, CABINET.y + 8];
const GEARBOX = { x: -16, y: -34, w: 28, d: 22, r: 2 };
const GEARBOX_H = 8;
const RAIL = { x: 14, y: LANE_Y - 7, w: 62, d: 14, r: 1.5 };   // the sorter rail bed
const RAIL_H = 4;
const CARD_PARK = [20, 30, 40];
const TEST_X = 54;
const TRAYS = { friends: [94, -36], near: [94, LANE_Y], out: [94, 10] };
const DIAL = [TEST_X, -36];
const DIAL_R = 7;
const MASK = { x: TEST_X - 7, y: 2, w: 14, d: 10, r: 1 };     // the window the busy mask slides over
const FLAP_X = TEST_X + 10;
const PHONES = { ana: [150, -34], luis: [150, 6] };
const PIPE_Z = 2.8;                                      // pipe centre: radius 1.6 plus a hair above the plate

const P = k.fitProjection(
  [...k.boxCorners(PLATE, -17, 0), [HOST[0], HOST[1], 36], [PHONES.ana[0], PHONES.ana[1], 36], [PLATTER[0], PLATTER[1], CABINET_H + 10]],
  WIDTH,
  HEIGHT,
  { pad: 26, azimuth: 48, elevation: 32 },
);
const sc = scene(P);
const { at, S, L, D } = sc;

// MARK: - Plate and engraving

sc.plate(PLATE, {
  engraving: [
    sc.label("HOST", HOST[0] + 2, 12),
    sc.label("API", ARCH[0], 10),
    sc.label("POSTGRES · create_hit", CABINET.x + CABINET.w / 2, CABINET.y + CABINET.d + 10),
    sc.label("FEED · get_play_feed", RAIL.x + RAIL.w / 2 - 6, 26),
    sc.label("FROM FRIENDS", TRAYS.friends[0], TRAYS.friends[1] - 14, { size: 2.8 }),
    sc.label("NEAR YOU", TRAYS.near[0] + 18, TRAYS.near[1], { size: 2.8 }),
    sc.label("NOT SHOWN", TRAYS.out[0], TRAYS.out[1] + 14, { size: 2.8 }),
    sc.label("PLAY TABS", PHONES.luis[0], PHONES.luis[1] + 20),
  ].join(""),
});

// MARK: - Host, door, cabinet

phone(sc, "host", HOST);
for (const dy of [-9, 9]) sc.slab(`arch.post${dy > 0 ? "F" : "B"}`, { x: ARCH[0] - 2, y: ARCH[1] + dy - 2, w: 4, d: 4, r: 1 }, 0, 12, { steps: 3, bevel: 0.4 });
sc.slab("arch.lintel", { x: ARCH[0] - 2.5, y: ARCH[1] - 11, w: 5, d: 22, r: 1 }, 12, 3, { steps: 3, bevel: 0.4, extra: D([at([ARCH[0], ARCH[1] - 9, 15]), at([ARCH[0], ARCH[1] + 9, 15])], { size: 0.45 }) });

const lane = { x: CABINET.x + 3, y: LANE_Y - 4, w: CABINET.w - 6, d: 8, r: 1.5 };
sc.slab("cabinet", CABINET, 0, CABINET_H, {
  tone: "hi", crease: "lo", steps: 5, bevel: 0.9,
  extra: L(k.planOutline(k.insetPlan(CABINET, 3), CABINET_H, P, 5), { tone: "faint" }) + L(k.planOutline(lane, CABINET_H, P, 3), { tone: "lo" })
    + D(k.corners(CABINET, 4).map(([x, y]) => at([x, y, CABINET_H])), { size: 0.45 }),
});
for (const [i, gx] of GATE_XS.entries()) {
  for (const gy of [LANE_Y - 9, LANE_Y + 9]) sc.slab(`gate${i}.post${gy < LANE_Y ? "B" : "F"}`, { x: gx - 1.5, y: gy - 1.5, w: 3, d: 3, r: 0.8 }, CABINET_H, 4, { steps: 3, bevel: 0.3 });
  sc.slab(`gate${i}.bar`, { x: gx - 1.2, y: LANE_Y - 10.5, w: 2.4, d: 21, r: 0.8 }, CABINET_H + 4, 2, { steps: 3, wrap: (s) => `<g data-gate="${i}">${s}</g>` });
}
platter(sc, "platter", PLATTER, CABINET_H, { r: 6.5, h: 9, rows: 3 });

// MARK: - The feed function: gearbox and sorter

sc.slab("gearbox", GEARBOX, 0, GEARBOX_H, { extra: L(k.planOutline(k.insetPlan(GEARBOX, 2), GEARBOX_H, P, 4), { tone: "faint" }) });
const GEARS = [
  gear(sc, "gear.big", [GEARBOX.x + 9, GEARBOX.y + 11], GEARBOX_H, { r: 6, teeth: 12 }),
  gear(sc, "gear.small", [GEARBOX.x + 9 + 10.7, GEARBOX.y + 11], GEARBOX_H, { r: 4.5, teeth: 9 }),
];

sc.slab("rail.bed", RAIL, 0, RAIL_H, { extra: L(k.lineOnTop([RAIL.x + 2, LANE_Y], [RAIL.x + RAIL.w - 2, LANE_Y], RAIL_H, P), { tone: "faint", free: true }) });
for (const y of [LANE_Y - 5.5, LANE_Y + 5.5]) sc.slab(`rail.${y < LANE_Y ? "back" : "front"}`, { x: RAIL.x + 1, y: y - 1, w: RAIL.w - 2, d: 2, r: 0.8 }, RAIL_H, 1.5, { steps: 3, bevel: 0.3 });

// Viewer cards, parked at the rail's start, moved by the page.
const CARD = { w: 8, d: 11 };   // wide enough to ride on both rails
M.VIEWERS.forEach((v, i) => {
  sc.slab(`card.${v.name}`, { x: CARD_PARK[i] - CARD.w / 2, y: LANE_Y - CARD.d / 2, w: CARD.w, d: CARD.d, r: 1 }, RAIL_H + 1.5, 1.6, {   // rests on the rails' tops
    tone: "hi", crease: "lo", steps: 3, bevel: 0.3, bias: 0.3,
    extra: L(k.lineOnTop([CARD_PARK[i] - 2.5, LANE_Y - 1], [CARD_PARK[i] + 2.5, LANE_Y - 1], RAIL_H + 3.1, P), { tone: "lo", free: true }),
    wrap: (s) => `<g data-card="${i}">${s}</g>`,
  });
});

// The test station: a distance dial behind the rail, a busy mask in front, a friends flap over it.
sc.slab("dial.stand", { x: DIAL[0] - DIAL_R - 2, y: DIAL[1] - DIAL_R - 2, w: DIAL_R * 2 + 4, d: DIAL_R * 2 + 4, r: 2 }, 0, 3, {});
sc.cyl("dial", DIAL[0], DIAL[1], DIAL_R, 3, 3, {
  tone: "hi", crease: "lo", steps: 40, bevel: 0.5,
  extra: (() => { const t = k.radialTicks(DIAL[0], DIAL[1], DIAL_R - 1.6, 20, 5, 6, [0.9, 1.8], P, -Math.PI / 2, Math.PI); return L(t.minor, { tone: "lo" }) + L(t.major, { tone: "mid" }) + L(k.ring(DIAL[0], DIAL[1], 0.9, 6, P, 10), { tone: "mid" }) + k.faceTextSvg(k.topMatrix([DIAL[0], DIAL[1] + 4.2], 6, P, "x"), "mi", { size: 2, tone: "lo", anchor: "middle" }); })(),
});
sc.slab("mask.frame", { x: MASK.x - 1.5, y: MASK.y - 1.5, w: MASK.w + 3, d: MASK.d + 3, r: 1.5 }, 0, 2, { extra: L(k.planOutline(MASK, 2, P, 3), { tone: "lo" }) + D(k.dotGrid(MASK.x + 2, MASK.y + 2, 4, 3, 3.2, 2, P), { size: 0.4, tone: "lo" }) });
sc.slab("mask.bar", { x: MASK.x - 1, y: MASK.y - 1.5 - 3, w: MASK.w + 2, d: 3, r: 0.8 }, 2, 1.6, { tone: "lo", steps: 3, wrap: (s) => `<g data-mask>${s}</g>` });
sc.slab("flap.hinge", { x: FLAP_X - 1.5, y: LANE_Y + 7.5, w: 3, d: 3, r: 0.8 }, 0, 10, { steps: 3 });
sc.slab("flap", { x: FLAP_X - 3, y: LANE_Y - 6, w: 6, d: 16, r: 1 }, 10, 1, { tone: "hi", crease: "lo", steps: 3, bias: 0.4, wrap: (s) => `<g data-flap>${s}</g>` });

// Trays.
for (const [name, [tx, ty]] of Object.entries(TRAYS)) {
  const plan = { x: tx - 8, y: ty - 6, w: 16, d: 12, r: 1.5 };
  sc.slab(`tray.${name}`, plan, 0, name === "out" ? 2 : 3, { tone: name === "out" ? "lo" : "mid", extra: L(k.planOutline(k.insetPlan(plan, 1.6), name === "out" ? 2 : 3, P, 3), { tone: "faint" }) });
}

// Phones with Play open.
phone(sc, "ana", PHONES.ana);
phone(sc, "luis", PHONES.luis);

// MARK: - Pipes

const ROUTES = {
  post: sc.pipe("pipe.post", [[HOST[0] + 12, HOST[1], PIPE_Z], [ARCH[0], ARCH[1], PIPE_Z], [CABINET.x, LANE_Y, PIPE_Z]], 1.6, { bend: 6 }),
  lane: [[CABINET.x + 3, LANE_Y, CABINET_H], [CABINET.x + CABINET.w - 3, LANE_Y, CABINET_H]],
  toAna: sc.pipe("pipe.ana", [[CABINET.x + 40, CABINET.y, PIPE_Z], [CABINET.x + 40, -52, PIPE_Z], [PHONES.ana[0] - 34, -52, PIPE_Z], [PHONES.ana[0] - 34, PHONES.ana[1], PIPE_Z], [PHONES.ana[0] - 12, PHONES.ana[1], PIPE_Z]], 1.6, { bend: 8 }),
  toLuis: sc.pipe("pipe.luis", [[CABINET.x + 60, CABINET.y + CABINET.d, PIPE_Z], [CABINET.x + 60, 36, PIPE_Z], [PHONES.luis[0] - 34, 36, PIPE_Z], [PHONES.luis[0] - 34, PHONES.luis[1], PIPE_Z], [PHONES.luis[0] - 12, PHONES.luis[1], PIPE_Z]], 1.6, { bend: 8 }),
};
const SCREEN_ROUTES = Object.fromEntries(Object.entries(ROUTES).map(([n, r]) => [n, routeTable(r, P)]));

// MARK: - Page

const start = M.storyAt(0);
const beads = ["post", "lane", "toAna", "toLuis"].map((n) => `<g class="pulse" data-pulse="${n}" opacity="0"><circle class="pulse-glow" r="5"/><circle class="pulse-core" r="2"/></g>`).join("");
const needleAt = (share) => {
  const a = -Math.PI / 2 + share * Math.PI;
  return k.lineOnTop([DIAL[0], DIAL[1]], [DIAL[0] + Math.sin(a) * (DIAL_R - 2.4), DIAL[1] - Math.cos(a) * (DIAL_R - 2.4)], 6.2, P);
};

const svgBody = sc.body() + `<path data-part="needle" class="iso-line" data-tone="lit" data-free="start" d="${needleAt(0)}" style="stroke-width:1"/>` + beads;
const svg = k.figureSvg({
  width: WIDTH,
  height: HEIGHT,
  label:
    "A bench of stations joined by pipes: a host's phone, an API door, a database cabinet with four lift gates and a platter, a gearbox, a sorter rail with three viewer cards, a distance dial, a busy mask and a friends flap, three trays, and two phones with the Play tab open.",
  body: [svgBody],
});

const modelScript = readFileSync(join(HERE, "model.mjs"), "utf8").replace(/^export /gm, "");
const gearSource = gearTeeth.toString().replace("k.lineOnTop", "lineOnTop");

const live = `
const P = ${JSON.stringify(P)};
const ROUTES = ${JSON.stringify(SCREEN_ROUTES)};
const GEARS = ${JSON.stringify(GEARS)};
const DIAL = ${JSON.stringify(DIAL)}, DIAL_R = ${DIAL_R}, LANE_Y = ${LANE_Y}, RAIL_H = ${RAIL_H}, TEST_X = ${TEST_X};
const CARD_PARK = ${JSON.stringify(CARD_PARK)}, TRAYS = ${JSON.stringify(TRAYS)};
const stage = document.querySelector(".iso-stage");
const svg = stage.querySelector("svg");
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");
const q = (s) => svg.querySelector(s);
const beads = Object.fromEntries(["post", "lane", "toAna", "toLuis"].map((n) => [n, q('[data-pulse="' + n + '"]')]));
const gateEls = [0, 1, 2, 3].map((i) => q('[data-gate="' + i + '"]'));
const cardEls = [0, 1, 2].map((i) => q('[data-card="' + i + '"]'));
const rowEls = [0, 1, 2].map((i) => q('[data-row="' + i + '"] .iso-line'));
const gearEls = GEARS.map((g, i) => q('[data-gear="' + (i ? "gear.small" : "gear.big") + '"]'));
const maskEl = q("[data-mask]"), flapEl = q("[data-flap]"), needle = q('[data-part="needle"]');
const screens = Object.fromEntries(["host", "ana", "luis"].map((n) => [n, q('[data-screen="' + n + '"]')]));
const gearTeeth = ${gearSource};
const needleAt = ${needleAt.toString().replace("k.lineOnTop", "lineOnTop")};
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
const place = (el, name, share) => {
  if (share === null) { el.setAttribute("opacity", "0"); return; }
  const [x, y] = pointAt(name, share);
  el.setAttribute("transform", "translate(" + x.toFixed(1) + " " + y.toFixed(1) + ")"); el.setAttribute("opacity", "1");
};
const lerp = (a, b, s) => a + (b - a) * s;
function cardPlace(i, card) {
  const park = CARD_PARK[i];
  let x, y = LANE_Y, z = 0;
  if (card.x <= 1) { x = lerp(park, TEST_X, card.x); }
  else {
    const s = card.x - 1, tray = TRAYS[card.tray];
    x = lerp(TEST_X, tray[0], s); y = lerp(LANE_Y, tray[1], s);
    z = card.tray === "out" ? -RAIL_H * Math.max(0, s - 0.6) / 0.4 : -(RAIL_H + 1.5 - 3) * s;   // lands on the tray's top, or drops into the chute
  }
  cardEls[i].setAttribute("transform", translateAlong(P, [x - park, y - LANE_Y, z]));
}
let clock = 0, playing = !still.matches, frame = 0, last = 0, visible = false, idleTimer = 0, shown = "";
function draw() {
  const s = storyAt(clock);
  // The post rides the pipe for the first 45% of its time, then the lane across the cabinet top.
  const p = s.pulses.post;
  place(beads.post, "post", p === null || p > 0.45 ? null : p / 0.45);
  place(beads.lane, "lane", p === null || p <= 0.45 ? null : (p - 0.45) / 0.55);
  place(beads.toAna, "toAna", s.pulses.toAna);
  place(beads.toLuis, "toLuis", s.pulses.toLuis);
  s.gates.forEach((lift, i) => gateEls[i].setAttribute("transform", translateAlong(P, [0, 0, lift * 5])));
  rowEls.forEach((el, i) => el.setAttribute("data-tone", s.stored && i === 0 ? "green" : "faint"));
  GEARS.forEach((g, i) => gearEls[i].setAttribute("d", gearTeeth(g.x, g.y, g.r, g.teeth, g.z, s.gearTurn * (i ? -GEARS[0].r / g.r : 1), P)));
  s.cards.forEach((card, i) => cardPlace(i, card));
  needle.setAttribute("d", needleAt(s.dial));
  maskEl.setAttribute("transform", translateAlong(P, [0, s.mask * 6.5, 0]));
  flapEl.setAttribute("transform", translateAlong(P, [0, 0, s.flap * 5]));
  for (const [n, el] of Object.entries(screens)) el.toggleAttribute("data-on", s.screens[n] === 1);
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
</style>`;

const body = k.plateHtml({
  fig: "Fig 3",
  title: "Posting a hit",
  hint: "Hover to scrub · space plays",
  readout: start.note,
  keys: [
    { mark: "lit", label: "The post, then the insert, on their way" },
    { mark: "raised", label: "Viewer cards: each player the feed function considers" },
    { mark: "green", label: "A row written, a screen that heard it" },
  ],
  caption:
    "Posting a hit. create_hit refuses a start under 15 minutes away or over 30 days out, more than 7 spots, or a 21st hit in a day, then stores the row. get_play_feed builds each player's list when they ask: a friend's hit goes under From friends, a stranger's under Near you ordered by the distance from the court to the player's home point over a spatial index, and a hit in an hour the player marked busy is left out. Phones with Play open hear the insert and refresh once, 400 ms later.",
  body: `${css}<div class="iso-stage" tabindex="0" role="slider" aria-label="Posting a hit: a story in ${M.LOOP} seconds. Arrow keys step through it, space plays and pauses" aria-valuemin="0" aria-valuemax="${M.LOOP}" aria-valuenow="0">${svg}</div>`,
});

const end = M.storyAt(M.LOOP - 0.01);
if (end.stored !== 1 || end.cards.some((c) => c.tray === null) || end.screens.ana !== 1 || end.screens.luis !== 1) {
  throw new Error(`The story does not end with the row stored, every card sorted and both Play tabs lit: ${JSON.stringify(end)}`);
}

const file = theme === "light" ? "index-light.html" : "index.html";
writeFileSync(join(HERE, file), k.pageHtml({ title: "Posting a hit", theme, body, script: kitScript() + modelScript + live }));
console.log("wrote", file, `${sc.R.items.length} items`);
sc.audit({});

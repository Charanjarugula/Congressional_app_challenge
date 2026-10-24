// Everyone hears it: sending a message so it lands on every phone at once.
//
// A bench of stations joined by wires. The sender's phone drops a hollow card into its own tray
// the moment the message is typed (the optimistic copy with its client_id), and a pulse leaves
// for the database cabinet. On the cabinet top the pulse passes four lift gates, the checks
// send_message makes in order (member, not blocked, clean words, under the rate limit), and a
// press stamps the id on; the card in the sender's tray fills in solid. From the cabinet the
// pulse reaches the Realtime board, which rings one wire per phone whose row-level security lets
// it see the row; one wire is cut, so that phone's poll clock fetches the page instead. A branch
// runs to the push booth, whose mast reaches the phone that is away. A second identical send
// stops at the tag reader on the cabinet's doorstep and comes straight back.
//
//   node docs/figures/everyone-hears-it/build.mjs            → index.html (dark)
//   node docs/figures/everyone-hears-it/build.mjs --light    → index-light.html

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as k from "../kit/iso-kit.mjs";
import { kitScript } from "../kit/inline.mjs";
import * as M from "./model.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const theme = process.argv.includes("--light") ? "light" : "dark";

const WIDTH = 640;
const HEIGHT = 380;

const PLATE = { x: -214, y: -58, w: 398, d: 116, r: 8 };
const PLATE_H = 12;
const FOOT_H = 5;

// Stations, left to right.
const SENDER = { x: -200, y: -18 };                 // the sender's phone cradle
const TRAY = { x: -170, y: -24, w: 22, d: 20, r: 2 };   // the sender's own message list
const CARD = { x: TRAY.x + 5, y: TRAY.y + 6, w: 12, d: 8, r: 1 };
const ARCH = { x: -132, y: -18 };                   // the API door the call goes through
const CABINET = { x: -108, y: -26, w: 92, d: 44, r: 3 };
const CABINET_H = 14;
const GATE_XS = M.GATE_AT.map((share) => CABINET.x + 10 + share * (CABINET.w - 24));
const PRESS_X = CABINET.x + CABINET.w - 10;
const READER = [CABINET.x - 6, -8];
const DRUM = [CABINET.x + 10, -17];
const BOARD = { x: 16, y: -30, w: 30, d: 60, r: 3 };
const BOARD_H = 6;
const BELLS = [-18, 0, 18].map((y) => [BOARD.x + 15, y]);
const PHONES = { a: [104, -40], b: [104, -14], c: [104, 12], d: [104, 40], e: [162, 0] };
const POLL = [PHONES.d[0] + 20, PHONES.d[1]];
const BOOTH = { x: 50, y: 34, w: 22, d: 18, r: 2 };
const BOOTH_H = 12;
const MAST = [BOOTH.x + 11, BOOTH.y + 9];
const MAST_TOP = BOOTH_H + 40;

const P = k.fitProjection(
  [...k.boxCorners(PLATE, -PLATE_H - FOOT_H, 0), [MAST[0], MAST[1], MAST_TOP + 4], [SENDER.x, SENDER.y, 40]],
  WIDTH,
  HEIGHT,
  { pad: 26, azimuth: 48, elevation: 32 },
);

const at = (point) => k.iso(point, P);
const S = (paths, style) => k.solidSvg(paths, style);
const L = (d, style) => k.lineSvg(d, style);
const D = (points, style) => k.dotsSvg(points, style);
const byDepth = (points) => [...points].sort((a, b) => k.depthOf([a[0], a[1], 0], P) - k.depthOf([b[0], b[1], 0], P));
const label = (text, x, y) => k.faceTextSvg(k.topMatrix([x, y], 0, P, "x"), text, { size: 3.6, tone: "mid", anchor: "middle" });

// MARK: - Base

function plate() {
  const out = [`<path class="iso-halo" d="${k.haloOf(PLATE, -PLATE_H - FOOT_H, PLATE_H, P)}"/>`];
  for (const [x, y] of byDepth(k.corners(PLATE, 22))) {
    out.push(S(k.cylinder(x, y, 7, -PLATE_H - FOOT_H, 1.6, P, 28), { tone: "lo" }));
    out.push(S(k.cylinder(x, y, 5.4, -PLATE_H - FOOT_H + 1.6, FOOT_H - 1.6, P, 28), { tone: "mid" }));
  }
  out.push(S(k.slabOf(PLATE, -PLATE_H, PLATE_H, P, 8, 1.6), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(PLATE, 5), 0, P), { tone: "lo" }));
  const screws = k.corners(PLATE, 10);
  out.push(L(screws.map(([x, y]) => k.ring(x, y, 2.2, 0, P, 16)).join(""), { tone: "lo" }));
  out.push(D(screws.map(([x, y]) => at([x, y, 0])), { size: 0.5 }));
  // Engraved station names along the front, the way a bench is labelled.
  out.push(label("SENDER", SENDER.x + 14, 10));
  out.push(label("API", ARCH.x, 10));
  out.push(label("POSTGRES · send_message", CABINET.x + CABINET.w / 2, CABINET.y + CABINET.d + 9));
  out.push(label("REALTIME", BOARD.x + BOARD.w / 2, BOARD.y + BOARD.d + 10));
  out.push(label("SEND-PUSH · APNS", BOOTH.x + BOOTH.w / 2, BOOTH.y + BOOTH.d + 8));
  out.push(label("MEMBERS", PHONES.d[0] - 2, PHONES.d[1] + 16));
  out.push(label("AWAY", PHONES.e[0], PHONES.e[1] + 16));
  return out.join("");
}

// MARK: - Phones

// A phone standing in a cradle, its screen on the face toward the viewer. `name` lets the page
// light the screen.
function phone([x, y], name, { clock = false } = {}) {
  const out = [];
  const cradle = { x: x - 12, y: y - 9, w: 24, d: 18, r: 2 };
  out.push(S(k.slabOf(cradle, 0, 4, P, 4, 0.6), { tone: "mid" }));
  out.push(D([at([cradle.x + 3, cradle.y + 3, 4]), at([cradle.x + cradle.w - 3, cradle.y + cradle.d - 3, 4])], { size: 0.45 }));
  const body = { x: x - 9, y: y - 1.5, w: 18, d: 3, r: 1 };
  out.push(S(k.slabOf(body, 4, 30, P, 3, 0.5), { tone: "hi", crease: "lo" }));
  // The screen, drawn in the plane of the near face (y = body.y + body.d).
  const face = k.sideMatrix([body.x + 1.5, body.y + body.d], 4 + 3, P, "left");
  out.push(`<g data-screen="${name}"><path class="screen" transform="${face}" d="M0 0H15V-24H0Z"/><path class="iso-line" data-tone="faint" transform="${face}" d="M0 0H15V-24H0Z"/></g>`);
  out.push(L(k.lineOnTop([body.x + 7, body.y + body.d], [body.x + 11, body.y + body.d], 4 + 30 - 2.4, P), { tone: "faint", free: true }));
  if (clock) {
    // The poll clock beside the phone whose socket is down.
    const [cx, cy] = POLL;
    out.push(S(k.cylinder(cx, cy, 6, 0, 3, P, 28), { tone: "mid" }));
    out.push(S(k.cylinder(cx, cy, 5, 3, 1.4, P, 28, 0.4), { tone: "hi", crease: "lo" }));
    const ticks = k.radialTicks(cx, cy, 4.2, 12, 3, 4.4, [0.8, 1.4], P);
    out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
    out.push(L(k.ring(cx, cy, 0.8, 4.4, P, 10), { tone: "mid" }));
  }
  return out.join("");
}

const pollNeedle = (ticks) => {
  const angle = (ticks / 8) * Math.PI * 2;
  const [x, y] = POLL;
  return k.lineOnTop([x, y], [x + Math.sin(angle) * 3.4, y - Math.cos(angle) * 3.4], 4.6, P);
};

// MARK: - Sender's tray and card

function tray() {
  const out = [];
  out.push(S(k.slabOf(TRAY, 0, 3, P, 3, 0.5), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(TRAY, 1.6), 3, P, 3), { tone: "faint" }));
  out.push(D([at([TRAY.x + 2, TRAY.y + 2, 3]), at([TRAY.x + TRAY.w - 2, TRAY.y + TRAY.d - 2, 3])], { size: 0.4 }));
  return out.join("");
}

function card() {
  return `<g data-card="0">${S(k.slabOf(CARD, 3, 1.2, P, 3), { tone: "hi", lit: true, crease: "lo" })}</g>`;
}

// MARK: - The API door

function arch() {
  const out = [];
  const { x, y } = ARCH;
  for (const dy of [-9, 9]) {
    out.push(S(k.slabOf({ x: x - 2, y: y + dy - 2, w: 4, d: 4, r: 1 }, 0, 12, P, 3, 0.4), { tone: "mid" }));
  }
  out.push(S(k.slabOf({ x: x - 2.5, y: y - 11, w: 5, d: 22, r: 1 }, 12, 3, P, 3, 0.4), { tone: "mid" }));
  out.push(D([at([x, y - 9, 15]), at([x, y + 9, 15])], { size: 0.45 }));
  return out.join("");
}

// MARK: - The database cabinet

function cabinet() {
  const out = [];
  out.push(S(k.slabOf(CABINET, 0, CABINET_H, P, 5, 0.9), { tone: "hi", crease: "lo", inner: L(k.sideSeam(CABINET, 7, P, 5), { tone: "faint" }) }));
  out.push(L(k.planOutline(k.insetPlan(CABINET, 3), CABINET_H, P, 5), { tone: "faint" }));
  out.push(D(k.corners(CABINET, 4).map(([x, y]) => at([x, y, CABINET_H])), { size: 0.45 }));
  // The path the pulse follows across the top: a shallow channel.
  const channel = { x: CABINET.x + 4, y: -4, w: PRESS_X - CABINET.x, d: 8, r: 1.5 };
  out.push(L(k.planOutline(channel, CABINET_H, P, 3), { tone: "lo" }));
  // Gate posts: the lift bars are separate so they can move.
  for (const gx of GATE_XS) {
    for (const gy of [-9, 9]) {
      out.push(S(k.slabOf({ x: gx - 1.5, y: gy - 1.5, w: 3, d: 3, r: 0.8 }, CABINET_H, 9, P, 3, 0.3), { tone: "mid" }));
    }
  }
  // The tag reader on the doorstep, where a repeated client_id turns round.
  out.push(S(k.slabOf({ x: READER[0] - 3, y: READER[1] - 3, w: 6, d: 6, r: 1 }, 0, 6, P, 3, 0.4), { tone: "mid" }));
  out.push(`<g data-reader>${S(k.cylinder(READER[0], READER[1], 2, 6, 2, P, 16, 0.3), { tone: "hi", crease: "lo" })}</g>`);
  // The stamp press: a post with a head that drops onto the channel.
  out.push(S(k.cylinder(PRESS_X, -11, 2.4, CABINET_H, 14, P, 20), { tone: "mid", crease: "none" }));
  out.push(L(k.sideArc(PRESS_X, -11, 2.4, CABINET_H + 7, P, 12), { tone: "faint" }));
  out.push(S(k.slabOf({ x: PRESS_X - 2, y: -12, w: 4, d: 12, r: 1 }, CABINET_H + 12, 2.5, P, 3), { tone: "mid" }));
  // The drum where rows live.
  out.push(S(k.cylinder(DRUM[0], DRUM[1], 6.5, CABINET_H, 9, P, 36, 0.6), { tone: "mid" }));
  // The platter's bands end on their own seam rings, so no rib floats.
  out.push(L(k.sideArc(DRUM[0], DRUM[1], 6.5, CABINET_H + 1.5, P, 24), { tone: "faint" }));
  out.push(L(k.sideArc(DRUM[0], DRUM[1], 6.5, CABINET_H + 7.5, P, 24), { tone: "faint" }));
  out.push(L(k.ring(DRUM[0], DRUM[1], 4.4, CABINET_H + 9, P, 32), { tone: "lo" }));
  out.push(L(k.knurl(DRUM[0], DRUM[1], 6.5, CABINET_H + 1.5, CABINET_H + 7.5, 36, P, 0.3), { tone: "faint" }));
  return out.join("");
}

function gateBar(gx) {
  return S(k.slabOf({ x: gx - 1.2, y: -9, w: 2.4, d: 18, r: 0.8 }, CABINET_H + 3, 2, P, 3), { tone: "mid" });
}

function pressHead() {
  return S(k.cylinder(PRESS_X, 0, 3.2, CABINET_H + 6, 3, P, 20, 0.4), { tone: "hi", crease: "lo" });
}

// MARK: - The Realtime board

function board() {
  const out = [];
  out.push(S(k.slabOf(BOARD, 0, BOARD_H, P, 4, 0.6), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(BOARD, 2.5), BOARD_H, P, 4), { tone: "faint" }));
  out.push(D(k.corners(BOARD, 3).map(([x, y]) => at([x, y, BOARD_H])), { size: 0.45 }));
  for (const [x, y] of BELLS) {
    out.push(S(k.cylinder(x, y, 1.6, BOARD_H, 7, P, 16), { tone: "mid", crease: "none" }));
    out.push(S(k.cylinder(x, y, 4.4, BOARD_H + 7, 3.6, P, 28, 0.5), { tone: "hi", crease: "lo" }));
    out.push(L(k.sideArc(x, y, 4.4, BOARD_H + 8.2, P, 16), { tone: "faint" }));
  }
  return out.join("");
}

// MARK: - The push booth

function booth() {
  const out = [];
  out.push(S(k.slabOf(BOOTH, 0, BOOTH_H, P, 4, 0.6), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(BOOTH, 2), BOOTH_H, P, 4), { tone: "faint" }));
  out.push(D(k.corners(BOOTH, 3).map(([x, y]) => at([x, y, BOOTH_H])), { size: 0.45 }));
  const [mx, my] = MAST;
  out.push(S(k.cylinder(mx, my, 3, BOOTH_H, 2, P, 20), { tone: "mid" }));
  out.push(S(k.cylinder(mx, my, 1.2, BOOTH_H + 2, MAST_TOP - BOOTH_H - 2, P, 12), { tone: "mid", crease: "none" }));
  for (const z of [BOOTH_H + 14, BOOTH_H + 26]) out.push(L(k.sideArc(mx, my, 1.2, z, P, 8), { tone: "faint" }));
  out.push(S(k.cylinder(mx, my, 2.6, MAST_TOP - 3, 3, P, 16), { tone: "hi", crease: "lo" }));
  out.push(L(k.ring(mx, my, 5, MAST_TOP - 1.5, P, 24), { tone: "lo" }));
  out.push(L(k.ring(mx, my, 7.5, MAST_TOP - 1.5, P, 32), { tone: "faint" }));
  return out.join("");
}

// MARK: - Wires

// Each wire is a 3D polyline; the page gets the screen points and moves pulses along them.
const WIRES = {
  send: [[SENDER.x + 12, SENDER.y + 2, 0], [ARCH.x - 12, -8, 0], [ARCH.x + 12, -8, 0], [READER[0] - 3, -8, 0]],
  cabinet: [[CABINET.x + 6, 0, CABINET_H], [PRESS_X, 0, CABINET_H]],
  toBoard: [[CABINET.x + CABINET.w, 0, 0], [BOARD.x, 0, 0]],
  fanA: [[BOARD.x + BOARD.w, -18, 0], [PHONES.a[0] - 12, -40, 0]],
  fanB: [[BOARD.x + BOARD.w, -6, 0], [PHONES.b[0] - 12, -14, 0]],
  fanC: [[BOARD.x + BOARD.w, 6, 0], [PHONES.c[0] - 12, 12, 0]],
  fanD1: [[BOARD.x + BOARD.w, 18, 0], [70, 30, 0]],                      // cut: the socket is down
  fanD2: [[82, 36, 0], [PHONES.d[0] - 12, 42, 0]],
  poll: [[PHONES.d[0] - 12, 50, 0], [CABINET.x + CABINET.w - 10, 50, 0], [CABINET.x + CABINET.w - 10, CABINET.y + CABINET.d, 0]],
  toPush: [[CABINET.x + CABINET.w - 30, CABINET.y + CABINET.d, 0], [CABINET.x + CABINET.w - 30, 44, 0], [BOOTH.x, 44, 0]],
  radio: [[MAST[0], MAST[1], MAST_TOP], [PHONES.e[0], PHONES.e[1], 34]],
};
const screenRoute = (points) => points.map((p) => at(p));
const ROUTES = Object.fromEntries(Object.entries(WIRES).map(([name, points]) => [name, screenRoute(points)]));

function wires() {
  const out = [];
  const wire = (name, style = {}) => {
    const pts = ROUTES[name];
    out.push(k.wireSvg(pts[0], pts[pts.length - 1], { via: pts.slice(1, -1), tone: "mid", size: 1.1, ...style }));
  };
  wire("send");
  wire("toBoard");
  wire("fanA"); wire("fanB"); wire("fanC");
  wire("fanD1"); wire("fanD2");   // the cut socket: both halves end on a terminal
  wire("poll", { dashed: true });
  wire("toPush");
  wire("radio", { dotted: true, ends: "to" });
  return out.join("");
}

// The channel across the cabinet top is a groove, drawn with the cabinet; pulses ride it.

// MARK: - Assembly

const start = M.storyAt(0);
const pulseNames = Object.keys(start.pulses);
const pulses = pulseNames.map((name) => `<g class="pulse" data-pulse="${name}" opacity="0"><circle class="pulse-glow" r="5"/><circle class="pulse-core" r="2"/></g>`).join("");

const svg = k.figureSvg({
  width: WIDTH,
  height: HEIGHT,
  label:
    "A bench of stations joined by wires: a sender's phone and tray, an API door, a database cabinet with four lift gates and a stamp press, a Realtime board with three bells, five member phones, and a push booth with a mast. A pulse leaves the phone, passes the gates, is stamped, rings the bells and reaches every phone, one by its poll clock and one by the mast.",
  body: [
    plate(),
    wires(),
    phone([SENDER.x, SENDER.y], "sender"),
    tray(),
    card(),
    arch(),
    cabinet(),
    GATE_XS.map((gx, i) => `<g data-gate="${i}">${gateBar(gx)}</g>`).join(""),
    `<g data-press>${pressHead()}</g>`,
    board(),
    booth(),
    phone(PHONES.a, "a"),
    phone(PHONES.b, "b"),
    phone(PHONES.c, "c"),
    phone(PHONES.d, "d", { clock: true }),
    `<path data-part="poll-needle" class="iso-line" data-tone="hi" data-free="start" d="${pollNeedle(0)}" style="stroke-width:0.9"/>`,
    phone(PHONES.e, "e"),
    pulses,
  ],
});

const modelScript = readFileSync(join(HERE, "model.mjs"), "utf8").replace(/^export /gm, "");

const live = `
const P = ${JSON.stringify(P)};
const ROUTES = ${JSON.stringify(ROUTES)};
const CABINET_H = ${CABINET_H}, PRESS_X = ${PRESS_X}, POLL = ${JSON.stringify(POLL)};
const stage = document.querySelector(".iso-stage");
const svg = stage.querySelector("svg");
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");
const pulseEls = Object.fromEntries(${JSON.stringify(pulseNames)}.map((n) => [n, svg.querySelector('[data-pulse="' + n + '"]')]));
const gateEls = [0, 1, 2, 3].map((i) => svg.querySelector('[data-gate="' + i + '"]'));
const pressEl = svg.querySelector("[data-press]");
const readerEl = svg.querySelector("[data-reader]");
const cardEl = svg.querySelector("[data-card]");
const screens = Object.fromEntries(["a", "b", "c", "d", "e", "sender"].map((n) => [n, svg.querySelector('[data-screen="' + n + '"]')]));
const needle = svg.querySelector('[data-part="poll-needle"]');
const pollNeedle = ${pollNeedle.toString().replace("k.lineOnTop", "lineOnTop")};
// Arc-length tables so a pulse moves at a steady speed along a bent wire.
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
// The fan pulse rides three wires at once, the cut wire none.
let clock = 0, playing = !still.matches, frame = 0, last = 0, visible = false, idleTimer = 0, shown = "";
const fanEls = ["fanA", "fanB", "fanC"].map((n) => { const c = pulseEls.fan.cloneNode(true); c.removeAttribute("data-pulse"); pulseEls.fan.parentNode.appendChild(c); return [n, c]; });
pulseEls.fan.remove();
function draw() {
  const s = storyAt(clock);
  place(pulseEls.send, "send", s.pulses.send);
  place(pulseEls.cabinet, "cabinet", s.pulses.cabinet);
  place(pulseEls.toBoard, "toBoard", s.pulses.toBoard);
  for (const [name, el] of fanEls) place(el, name, s.pulses.fan);
  place(pulseEls.toPush, "toPush", s.pulses.toPush);
  place(pulseEls.radio, "radio", s.pulses.radio);
  place(pulseEls.poll, "poll", s.pulses.poll);
  place(pulseEls.pollBack, "poll", s.pulses.pollBack, true);
  place(pulseEls.dupe, "send", s.pulses.dupe);
  place(pulseEls.dupeBack, "send", s.pulses.dupeBack, true);
  s.gates.forEach((lift, i) => gateEls[i].setAttribute("transform", translateAlong(P, [0, 0, lift * 6])));
  pressEl.setAttribute("transform", translateAlong(P, [0, 0, -s.press * 5]));
  readerEl.toggleAttribute("data-on", s.reader > 0.3);
  cardEl.setAttribute("data-card", String(s.card));
  for (const [n, el] of Object.entries(screens)) el.toggleAttribute("data-on", n === "sender" ? s.card > 0 : s.screens[n] === 1);
  needle.setAttribute("d", pollNeedle(s.ticks));
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
stage.addEventListener("pointermove", (event) => {
  const box = svg.getBoundingClientRect();
  scrub(((event.clientX - box.left) / box.width) * LOOP);
});
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
.iso-wire .iso-line{stroke-width:0.9}
.screen{fill:var(--anatomy-paper)}
[data-screen][data-on] .screen{fill:var(--anatomy-green);opacity:.75}
[data-card="0"]{display:none}
[data-card="1"] .iso-fill,[data-card="1"] .iso-top,[data-card="1"] .iso-shade{opacity:0}
[data-card="1"] .iso-edge{stroke-dasharray:1.2 1.2}
[data-reader][data-on] .iso-top{fill:var(--anatomy-green)}
[data-reader][data-on] .iso-edge{stroke:var(--anatomy-green)}
</style>`;

const body = k.plateHtml({
  fig: "Fig 2",
  title: "Everyone hears it",
  hint: "Hover to scrub · space plays",
  readout: start.note,
  keys: [
    { mark: "lit", label: "The message, on its way" },
    { mark: "dotted", label: "Shown before it is stored: the hollow copy with its client_id" },
    { mark: "green", label: "A screen or lamp the database lit" },
    { mark: "dashed", label: "The poll, for a phone whose socket is down" },
  ],
  caption:
    "Sending a message. The sender's phone shows it at once as a hollow card tagged with a client_id and calls send_message. The database checks membership, blocks, words and the rate limit in that order, stores the row and stamps its id; the hollow card becomes that row. The insert reaches every phone allowed to see it over one socket each; a phone whose socket is down polls instead, and a phone that is away gets a push through send-push and APNs. Sending the same tag again returns the stored row and stores nothing.",
  body: `${css}<div class="iso-stage" tabindex="0" role="slider" aria-label="Everyone hears it: a story in ${M.LOOP} seconds. Arrow keys step through it, space plays and pauses" aria-valuemin="0" aria-valuemax="${M.LOOP}" aria-valuenow="0">${svg}</div>`,
});

const end = M.storyAt(M.LOOP - 0.01);
if (end.stored !== 1 || end.card !== 2 || Object.values(end.screens).some((v) => v !== 1)) {
  throw new Error(`The story does not end with one stored row on every screen: ${JSON.stringify(end)}`);
}

const file = theme === "light" ? "index-light.html" : "index.html";
writeFileSync(join(HERE, file), k.pageHtml({ title: "Everyone hears it", theme, body, script: kitScript() + modelScript + live }));
console.log("wrote", file);

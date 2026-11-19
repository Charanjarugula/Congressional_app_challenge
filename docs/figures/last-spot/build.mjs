// The last spot: how a hit fills, and why two accepts can't both take it.
//
// A booking tray with two seats (the hit's spots) stands at the end of a rail. Player tokens roll
// up the rail; a spring bolt (the row lock that respond_to_request takes with `select … for update`)
// lets one through at a time. The first player in raises the CONFIRMED flag and lights the chat
// lamp (add_player marks the hit confirmed and ensure_hit_chat opens its chat in the same
// transaction). When both seats are taken the bolt stays shut and the waiting player rolls back
// (every pending request expires with "filled up before the host could answer you"). The dial is
// pg_cron, one tick every five minutes; the lamp beside it lights once when the hour-before
// reminder goes out.
//
//   node docs/figures/last-spot/build.mjs            → index.html (dark)
//   node docs/figures/last-spot/build.mjs --light    → index-light.html

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as k from "../kit/iso-kit.mjs";
import { kitScript } from "../kit/inline.mjs";
import * as M from "./model.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const theme = process.argv.includes("--light") ? "light" : "dark";

const WIDTH = 600;
const HEIGHT = 380;

// World: x and y on the floor, z up, about 1 px each. The tray stands at the back left, the rail
// runs toward it from the right, the scheduler dial sits at the front right.
const PLATE = { x: -132, y: -70, w: 286, d: 112, r: 8 };
const PLATE_H = 12;
const FOOT_H = 5;

const TRAY = { x: -40, y: -56, w: 84, d: 36, r: 3 };
const TRAY_H = 8;
const TRAY_TOP = TRAY_H;
const SEATS = M.SEAT_X.map((x) => ({ x: x - 11, y: M.RAIL_Y - 10, w: 22, d: 20, r: 2.5 }));

const BED = { x: TRAY.x + TRAY.w, y: M.RAIL_Y - 13, w: 150 - (TRAY.x + TRAY.w), d: 26, r: 2 };
const BED_H = 5;
const RAIL_H = 3;
const RAIL_TOP = BED_H + RAIL_H;   // = TRAY_TOP, so a token rolls straight into the tray
const RAILS = [M.RAIL_Y - 7, M.RAIL_Y + 4];

const TOKEN_R = 7;
const TOKEN_H = 5;

const GATE_X = TRAY.x + TRAY.w;        // the tray's right face, where the bolt crosses the opening
const BOLT = { x: GATE_X - 1, y: M.RAIL_Y - 9, w: 4, d: 18, r: 1 };   // closed: across the opening
const BOLT_Z = TRAY_TOP;
const BOLT_H = 7;
const HOUSING = { x: GATE_X - 3, y: M.RAIL_Y + 9, w: 8, d: 22, r: 1.5 };
const HOUSING_H = 11;
const SPRING_POST = [GATE_X + 1, TRAY.y - 6];
const SPRING_Z = BOLT_Z + 2.5;

const FLAG_POST = [TRAY.x + 24, TRAY.y - 5];
const FLAG = { x: FLAG_POST[0] - 16, y: FLAG_POST[1] - 1, w: 14, d: 2, r: 0.6 };
const FLAG_H = 10;

const LAMP = [TRAY.x + 10, TRAY.y + TRAY.d + 12];
const DIAL = [-92, 12];
const DIAL_R = 20;
const DIAL_Z = 4;
const DIAL_H = 8;
const DIAL_TOP = DIAL_Z + DIAL_H;
const REMIND = [DIAL[0] + 36, DIAL[1] + 8];

const P = k.fitProjection(
  [...k.boxCorners(PLATE, -PLATE_H - FOOT_H, 0), [FLAG_POST[0], FLAG_POST[1], TRAY_TOP + M.FLAG_RISE + 6], [LAMP[0], LAMP[1], 26], [DIAL[0] - DIAL_R, DIAL[1], DIAL_TOP + 3]],
  WIDTH,
  HEIGHT,
  { pad: 30, azimuth: 50 },
);

const at = (point) => k.iso(point, P);
const S = (paths, style) => k.solidSvg(paths, style);
const L = (d, style) => k.lineSvg(d, style);
const D = (points, style) => k.dotsSvg(points, style);
const byDepth = (points) => [...points].sort((a, b) => k.depthOf([a[0], a[1], 0], P) - k.depthOf([b[0], b[1], 0], P));

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

  // A minutes rule along the front edge: one major every 5 minutes, the dial's own step.
  const strip = { x: -56, y: PLATE.y + PLATE.d - 13, w: 200, d: 7, r: 1 };
  out.push(S(k.slabOf(strip, 0, 0.6, P, 3), { tone: "lo", crease: "none" }));
  const ticks = k.topTicks(strip.x + 4, strip.x + strip.w - 4, 4, 5, strip.y + 0.8, 0.6, [2, 3.6], P);
  out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
  out.push(D([at([strip.x + 2, strip.y + 3.5, 0.6]), at([strip.x + strip.w - 2, strip.y + 3.5, 0.6])], { size: 0.45 }));

  // The label plate at the front left, its rule lines standing for the hit's details.
  const label = { x: -44, y: 4, w: 46, d: 20, r: 2 };
  out.push(S(k.slabOf(label, 0, 0.8, P, 4), { tone: "mid", crease: "none" }));
  out.push(L(k.planOutline(k.insetPlan(label, 1.6), 0.8, P), { tone: "faint" }));
  for (const [i, w] of [30, 22, 26].entries()) {
    out.push(L(k.lineOnTop([label.x + 5, label.y + 6 + i * 5], [label.x + 5 + w, label.y + 6 + i * 5], 0.8, P), { tone: "lo", free: true }));
  }
  out.push(D([at([label.x + 3, label.y + 3, 0.8]), at([label.x + label.w - 3, label.y + label.d - 3, 0.8])], { size: 0.45 }));
  return out.join("");
}

// MARK: - Rail and tray

function bed() {
  const out = [];
  out.push(S(k.slabOf(BED, 0, BED_H, P, 4, 0.6), { tone: "mid" }));
  for (const y of RAILS) {
    out.push(S(k.slabOf({ x: BED.x + 2, y, w: BED.w - 4, d: 3, r: 1 }, BED_H, RAIL_H, P, 3, 0.4), { tone: "mid" }));
    out.push(D([BED.x + 8, BED.x + BED.w - 8].map((x) => at([x, y + 1.5, RAIL_TOP])), { size: 0.4 }));
  }
  // The end stop where the queue starts.
  const stop = { x: BED.x + BED.w - 5, y: M.RAIL_Y - 11, w: 4, d: 22, r: 1 };
  out.push(S(k.slabOf(stop, BED_H, 9, P, 3, 0.5), { tone: "mid" }));
  out.push(D([at([stop.x + 2, stop.y + 3, BED_H + 9]), at([stop.x + 2, stop.y + stop.d - 3, BED_H + 9])], { size: 0.45 }));
  return out.join("");
}

function tray() {
  const out = [];
  out.push(S(k.slabOf(TRAY, 0, TRAY_H, P, 5, 0.8), { tone: "hi", crease: "lo" }));
  out.push(L(k.planOutline(k.insetPlan(TRAY, 2.5), TRAY_TOP, P, 5), { tone: "faint" }));
  // Two seats, each a groove with an inner ring: where a token comes to rest.
  for (const seat of SEATS) {
    out.push(L(k.planOutline(seat, TRAY_TOP, P, 4), { tone: "lo" }));
    out.push(L(k.planOutline(k.insetPlan(seat, 2), TRAY_TOP, P, 4), { tone: "faint" }));
    out.push(L(k.ring(seat.x + seat.w / 2, seat.y + seat.d / 2, 1.4, TRAY_TOP, P, 12), { tone: "faint" }));
  }
  // The opening in the right face where tokens come in: a lip either side of the rail.
  const screws = k.corners(TRAY, 4).filter(([x]) => x < TRAY.x + 10);
  out.push(D(screws.map(([x, y]) => at([x, y, TRAY_TOP])), { size: 0.45 }));
  return out.join("");
}

// The flag plate, built at rest (down in its slot, hidden by the tray) and lifted with translateAlong.
function flag() {
  return S(k.slabOf(FLAG, -FLAG_H - 2, FLAG_H + 4, P, 3, 0.4), { tone: "hi", lit: true, crease: "lo" });
}

// MARK: - Gate

function springBack(open) {
  const from = SPRING_POST[1] + 1.5;   // starts inside the post, under its collar
  const to = BOLT.y + open * M.BOLT_TRAVEL + 1.2;   // the last turn hooks onto the bolt's back face
  return k.coil(from, to, [GATE_X + 1, SPRING_Z], 2.6, 5, "y", P);
}

function gateBack() {
  const out = [];
  // The flag's slot and post, behind the tray's back wall: the flag hides in it until the hit confirms.
  out.push(L(k.planOutline(k.insetPlan(FLAG, -0.8), 0, P, 3), { tone: "lo" }));
  out.push(S(k.cylinder(FLAG_POST[0], FLAG_POST[1], 2.2, 0, TRAY_TOP + 10, P, 20), { tone: "mid", crease: "none" }));
  out.push(L(k.sideArc(FLAG_POST[0], FLAG_POST[1], 2.2, TRAY_TOP + 2, P, 12), { tone: "faint" }));
  out.push(S(k.cylinder(FLAG_POST[0], FLAG_POST[1], 2.8, TRAY_TOP + 10, 1.6, P, 20), { tone: "mid" }));
  // The post the bolt's return spring pulls from, behind the tray's back edge.
  out.push(S(k.cylinder(SPRING_POST[0], SPRING_POST[1], 3, 0, SPRING_Z + 2, P, 20), { tone: "mid", crease: "none" }));
  out.push(L(k.sideArc(SPRING_POST[0], SPRING_POST[1], 3, SPRING_Z - 4, P, 12), { tone: "faint" }));
  out.push(S(k.cylinder(SPRING_POST[0], SPRING_POST[1], 3.6, SPRING_Z + 2, 1.4, P, 20), { tone: "mid" }));
  return out.join("");
}

function bolt() {
  const out = [];
  out.push(S(k.slabOf(BOLT, BOLT_Z, BOLT_H, P, 3, 0.5), { tone: "mid" }));
  // A knob on top to pull it by.
  out.push(S(k.cylinder(BOLT.x + 2, BOLT.y + BOLT.d - 4, 1.8, BOLT_Z + BOLT_H, 2.4, P, 16), { tone: "mid" }));
  out.push(L(k.knurl(BOLT.x + 2, BOLT.y + BOLT.d - 4, 1.8, BOLT_Z + BOLT_H, BOLT_Z + BOLT_H + 2.4, 12, P), { tone: "lo" }));
  return out.join("");
}

function springCollar() {
  return S(k.cylinder(SPRING_POST[0], SPRING_POST[1], 3.6, SPRING_Z - 2.2, 4.4, P, 20), { tone: "mid" });
}

function housing() {
  const out = [];
  out.push(S(k.slabOf(HOUSING, BED_H, HOUSING_H, P, 4, 0.6), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(HOUSING, 1.4), BED_H + HOUSING_H, P, 4), { tone: "faint" }));
  out.push(D([at([HOUSING.x + 2, HOUSING.y + HOUSING.d - 3, BED_H + HOUSING_H]), at([HOUSING.x + HOUSING.w - 2, HOUSING.y + HOUSING.d - 3, BED_H + HOUSING_H])], { size: 0.45 }));
  return out.join("");
}

// MARK: - Lamps and dial

function lamp(center, z0, height, name) {
  const [x, y] = center;
  const out = [];
  out.push(S(k.cylinder(x, y, 4.2, z0, 1.6, P, 24), { tone: "lo" }));
  out.push(S(k.cylinder(x, y, 2, z0 + 1.6, height - 6, P, 16), { tone: "mid", crease: "none" }));
  out.push(L(k.sideArc(x, y, 2, z0 + 1.6 + (height - 6) / 2, P, 10), { tone: "faint" }));
  out.push(S(k.cylinder(x, y, 3.2, z0 + height - 4.4, 1.2, P, 20), { tone: "mid" }));
  out.push(`<g data-lamp="${name}">${S(k.cylinder(x, y, 2.8, z0 + height - 3.2, 3.2, P, 20, 0.5), { tone: "hi", crease: "lo" })}</g>`);   // lit from the page: data-on
  return out.join("");
}

function dial() {
  const out = [];
  const [x, y] = DIAL;
  const stand = { x: x - DIAL_R - 4, y: y - DIAL_R - 4, w: DIAL_R * 2 + 8, d: DIAL_R * 2 + 8, r: 4 };
  out.push(S(k.slabOf(stand, 0, DIAL_Z, P, 5, 0.6), { tone: "mid" }));
  out.push(S(k.cylinder(x, y, DIAL_R, DIAL_Z, DIAL_H, P, 64, 0.8), { tone: "hi", crease: "lo" }));
  out.push(L(k.knurl(x, y, DIAL_R, DIAL_TOP - 3, DIAL_TOP, 72, P, 0.3), { tone: "lo" }));
  out.push(L(k.sideArc(x, y, DIAL_R, DIAL_TOP - 3, P, 40), { tone: "faint" }));
  out.push(L(k.ring(x, y, DIAL_R - 2.2, DIAL_TOP, P, 64), { tone: "lo" }));
  // Twelve majors: one every five minutes round the hour.
  const ticks = k.radialTicks(x, y, DIAL_R - 3, 60, 5, DIAL_TOP, [1.3, 2.8], P);
  out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
  out.push(L(k.ring(x, y, 1.6, DIAL_TOP, P, 16), { tone: "mid" }));
  out.push(k.faceTextSvg(k.topMatrix([x, y + 9], DIAL_TOP, P, "x"), "5 min", { size: 2.4, tone: "lo", anchor: "middle" }));
  // A crown on the +x side.
  out.push(S(k.slabOf({ x: x + DIAL_R - 1, y: y - 2.4, w: 5, d: 4.8, r: 1.2 }, DIAL_Z + 2, 5, P, 3), { tone: "mid" }));
  return out.join("");
}

const needleAt = (ticks) => {
  const angle = (ticks / 12) * Math.PI * 2;
  const [x, y] = DIAL;
  return k.lineOnTop([x - Math.sin(angle) * 3.4, y + Math.cos(angle) * 3.4], [x + Math.sin(angle) * (DIAL_R - 4), y - Math.cos(angle) * (DIAL_R - 4)], DIAL_TOP + 0.2, P);
};

// MARK: - Tokens

function token() {
  const out = [];
  out.push(S(k.cylinder(0, 0, TOKEN_R, 0, TOKEN_H, P, 28, 0.6), { tone: "hi", crease: "lo" }));
  out.push(L(k.ring(0, 0, TOKEN_R - 2.2, TOKEN_H, P, 28), { tone: "faint" }));
  out.push(L(k.ring(0, 0, 1.2, TOKEN_H, P, 12), { tone: "lo" }));
  return out.join("");
}

const start = M.storyAt(0);
const tokenAt = (which, state) => k.translateAlong(P, [state[which].x, M.RAIL_Y, RAIL_TOP + state[which].z]);

// Painter's order: plate, bed and rails, the spring post, the tray, the spring's back half, the
// bolt, the spring's front half, the housing (the bolt slides into it, so it is in front), then the
// tokens from far to near along the rail, the flag, the lamps and the dial.
const svg = k.figureSvg({
  width: WIDTH,
  height: HEIGHT,
  label:
    "A booking tray with two seats at the end of a rail. Player tokens roll up the rail toward a spring bolt that lets one into the tray at a time; the first one in raises a flag and lights a lamp, the second fills the tray, and a third rolls back. A dial beside it ticks every five minutes and a second lamp lights once for the reminder.",
  body: [
    plate(),
    bed(),
    gateBack(),
    `<g data-part="flag" transform="${k.translateAlong(P, [0, 0, 0])}">${flag()}</g>`,
    tray(),
    `<path data-part="spring-back" class="iso-line" data-tone="lo" d="${springBack(0).back}"/>`,
    `<g data-part="bolt" transform="${k.translateAlong(P, [0, 0, 0])}">${bolt()}</g>`,
    `<path data-part="spring-front" class="iso-line" data-tone="mid" d="${springBack(0).front}"/>`,
    springCollar(),
    housing(),
    `<g data-part="a" transform="${tokenAt("a", start)}">${token()}</g>`,
    `<g data-part="b" transform="${tokenAt("b", start)}">${token()}</g>`,
    `<g data-part="c" transform="${tokenAt("c", start)}">${token()}</g>`,
    lamp(LAMP, 0, 24, "chat"),
    dial(),
    `<path data-part="needle" class="iso-line" data-tone="lit" data-free="start" d="${needleAt(0)}" style="stroke-width:1.1"/>`,
    lamp(REMIND, 0, 16, "remind"),
  ],
});

// The model's source goes into the page as it is, minus the exports, so the page and the build
// agree on every number.
const modelScript = readFileSync(join(HERE, "model.mjs"), "utf8").replace(/^export /gm, "");

const live = `
const P = ${JSON.stringify(P)};
const RAIL_TOP = ${RAIL_TOP}, GATE_FACE = ${GATE_X}, SPRING_Z = ${SPRING_Z};
const BOLT = ${JSON.stringify(BOLT)}, SPRING_POST = ${JSON.stringify(SPRING_POST)}, DIAL = ${JSON.stringify(DIAL)}, DIAL_R = ${DIAL_R}, DIAL_TOP = ${DIAL_TOP};
const stage = document.querySelector(".iso-stage");
const svg = stage.querySelector("svg");
const part = (name) => svg.querySelector('[data-part="' + name + '"]');
const parts = { a: part("a"), b: part("b"), c: part("c"), bolt: part("bolt"), flag: part("flag"), needle: part("needle"), springBack: part("spring-back"), springFront: part("spring-front") };
const lamps = { chat: svg.querySelector('[data-lamp="chat"]'), remind: svg.querySelector('[data-lamp="remind"]') };
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");
const needleAt = ${needleAt.toString().replace("k.lineOnTop", "lineOnTop")};
const springAt = (open) => coil(SPRING_POST[1] + 1.5, BOLT.y + open * BOLT_TRAVEL + 1.2, [GATE_FACE + 1, SPRING_Z], 2.6, 5, "y", P);
let clock = 0, playing = !still.matches, frame = 0, last = 0, visible = false, idleTimer = 0, shown = "";
function draw() {
  const s = storyAt(clock);
  for (const name of ["a", "b", "c"]) parts[name].setAttribute("transform", translateAlong(P, [s[name].x, RAIL_Y, RAIL_TOP + s[name].z]));
  parts.bolt.setAttribute("transform", translateAlong(P, [0, s.bolt * BOLT_TRAVEL, 0]));
  const spring = springAt(s.bolt);
  parts.springBack.setAttribute("d", spring.back);
  parts.springFront.setAttribute("d", spring.front);
  parts.flag.setAttribute("transform", translateAlong(P, [0, 0, s.flag * FLAG_RISE]));
  parts.needle.setAttribute("d", needleAt(s.ticks));
  lamps.chat.toggleAttribute("data-on", s.lamp === 1);
  lamps.remind.toggleAttribute("data-on", s.remind === 1);
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
// The video render drives the clock from outside; the page exposes it for that.
window.__story = { seek: (t) => { playing = false; clearTimeout(idleTimer); clock = t; draw(); }, loop: LOOP };
draw();
`;

const body = k.plateHtml({
  fig: "Fig 1",
  title: "The last spot",
  hint: "Hover to scrub · space plays",
  readout: start.note,
  keys: [
    { mark: "raised", label: "Players asking to join, one seat each" },
    { mark: "lit", label: "The flag: the hit is confirmed, and its chat is open" },
    { mark: "green", label: "A lamp lit by the database: chat opened, reminder sent" },
  ],
  caption:
    "A hit with two spots. Accepting a player locks the hit's row first, so two accepts at the same moment take turns: the bolt opens for one token at a time. The first player confirms the hit and opens its chat in the same transaction; when the seats are full every other request expires. The dial is the scheduler, one tick every five minutes, and the hour-before reminder lights its lamp exactly once.",
  body: `<style>[data-lamp][data-on] .iso-top{fill:var(--anatomy-green)}[data-lamp][data-on] .iso-shade{fill:var(--anatomy-green);opacity:.55}[data-lamp][data-on] .iso-edge{stroke:var(--anatomy-green)}</style><div class="iso-stage" tabindex="0" role="slider" aria-label="The last spot: a story in ${M.LOOP} seconds. Arrow keys step through it, space plays and pauses" aria-valuemin="0" aria-valuemax="${M.LOOP}" aria-valuenow="0">${svg}</div>`,
});

// The build fails if the story no longer ends where the caption says it does.
const end = M.storyAt(M.LOOP - 0.01);
if (end.spots !== 0 || end.status !== "full" || end.remind !== 1 || end.lamp !== 1) {
  throw new Error(`The story does not end full, confirmed and reminded: ${JSON.stringify(end)}`);
}

const file = theme === "light" ? "index-light.html" : "index.html";
writeFileSync(join(HERE, file), k.pageHtml({ title: "The last spot", theme, body, script: kitScript() + modelScript + live }));
console.log("wrote", file);

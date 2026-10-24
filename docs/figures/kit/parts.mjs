// Parts the figures share, drawn with the kit and recorded for its audit at the same time:
// a scene that collects items and settles their painter's order from true depth, and the
// recurring machines (a phone in a cradle, a platter, a gear, a booth, a pipe that carries beads).

import * as k from "./iso-kit.mjs";
import * as G from "./lathe.mjs";
import * as A from "./audit.mjs";
import { tubePieces, tubeSvg } from "./tube.mjs";

export { k, G, A };

/// Everything drawn goes through `put`, so the audit sees a shape for every part and the order
/// of the items comes from measured depth rather than from hand-set keys.
export function scene(P) {
  const R = A.recorder(P);
  const KS = G.scaleOf(P);
  const at = (p) => k.iso(p, P);
  const S = (paths, style) => k.solidSvg(paths, style);
  const L = (d, style) => k.lineSvg(d, style);
  const D = (points, style) => k.dotsSvg(points, style);
  const fixed = [];   // static markup under every item: the plate, its engraving, the wires

  const put = (name, ref, svg, shapes = [], { bias = 0, ...rest } = {}) => R.put({ name, at: ref, bias, svg, shapes, piece: "fig", ...rest });
  const record = R.solid;

  /// A rounded box. `extra` is markup drawn with it (its screws, an inset outline), so the item's
  /// recorded shape still covers what it draws.
  const slab = (name, plan, z, h, { tone = "mid", steps = 4, bevel = 0.6, crease, lit, extra = "", bias = 0, wrap = (s) => s } = {}) => {
    const shape = record(A.slab(plan, z, h, { name }, steps));
    put(name, [plan.x + plan.w / 2, plan.y + plan.d / 2, z + h / 2], wrap(S(k.slabOf(plan, z, h, P, steps, bevel), { tone, crease, lit }) + extra), [shape], { bias });
    return shape;
  };

  const cyl = (name, cx, cy, r, z, h, { tone = "mid", steps = 24, bevel = 0, crease, lit, extra = "", bias = 0, wrap = (s) => s } = {}) => {
    const shape = record(A.cylinder(cx, cy, r, z, h, { name }));
    put(name, [cx, cy, z + h / 2], wrap(S(k.cylinder(cx, cy, r, z, h, P, steps, bevel), { tone, crease, lit }) + extra), [shape], { bias });
    return shape;
  };

  /// A pipe between stations, laid out as straight legs and filleted. Returns the route (3D) so
  /// the page can run beads along it. `shells` puts a connector at an end that lands on a part.
  const pipe = (name, points, r = 1.6, { tone = "mid", bend = 4, maxLength = 14, bias = 0.05, rings } = {}) => {
    const route = G.fillet(points, Math.max(bend, r * 2.6), 10, { P, tube: r });
    R.route(name, route, r, { limp: false, piece: "fig" });
    tubePieces(route, r, P, { maxLength, spacing: Math.max(0.6, Math.min(1.6, r)), ...(rings ? { rings } : {}) }).forEach((piece, index) =>
      put(`${name}:${index}`, piece.mid, tubeSvg(piece, { tone }), [A.tube(piece.points, piece.radii)], { bias, route: name, chunk: index, attrs: ` data-route="${name}" data-chunk="${index}"` }),
    );
    return route;
  };

  /// The base plate on feet, with corner screws and a groove, recorded as the ground.
  const plate = (PLATE, { h = 12, foot = 5, engraving = "" } = {}) => {
    const out = [`<path class="iso-halo" d="${k.haloOf(PLATE, -h - foot, h, P)}"/>`];
    const byDepth = (pts) => [...pts].sort((a, b) => k.depthOf([a[0], a[1], 0], P) - k.depthOf([b[0], b[1], 0], P));
    for (const [x, y] of byDepth(k.corners(PLATE, 22))) {
      out.push(S(k.cylinder(x, y, 7, -h - foot, 1.6, P, 28), { tone: "lo" }));
      out.push(S(k.cylinder(x, y, 5.4, -h - foot + 1.6, foot - 1.6, P, 28), { tone: "mid" }));
      record(A.cylinder(x, y, 7, -h - foot, foot, { name: "stand.foot", ground: true }));
    }
    out.push(S(k.slabOf(PLATE, -h, h, P, 8, 1.6), { tone: "mid" }));
    out.push(L(k.planOutline(k.insetPlan(PLATE, 5), 0, P), { tone: "lo" }));
    const screws = k.corners(PLATE, 10);
    out.push(L(screws.map(([x, y]) => k.ring(x, y, 2.2, 0, P, 16)).join(""), { tone: "lo" }));
    out.push(D(screws.map(([x, y]) => at([x, y, 0])), { size: 0.5 }));
    out.push(engraving);
    record(A.slab(PLATE, -h, h, { name: "stand.plate", ground: true }, 8));
    fixed.push(out.join(""));
  };

  /// A station name engraved on the plate.
  const label = (text, x, y, { size = 3.6, tone = "mid" } = {}) => k.faceTextSvg(k.topMatrix([x, y], 0, P, "x"), text, { size, tone, anchor: "middle" });

  /// The sorted items, each in a group that carries its name.
  const body = () => {
    A.settle(R, P);
    R.items.sort((a, b) => a.key - b.key);
    return fixed.join("") + R.items.map((item) => `<g class="it" data-name="${item.name}"${item.attrs ?? ""}>${item.svg}</g>`).join("");
  };

  const audit = (options = {}) => A.auditOrExit(R, P, options);

  return { R, KS, P, at, S, L, D, put, record, slab, cyl, pipe, plate, label, body, audit, fixed };
}

// MARK: - Machines

/// A phone standing in a cradle, its screen on the face toward the viewer; the page lights the
/// screen through `[data-screen="name"][data-on]`.
export function phone(sc, name, [x, y], { height = 30 } = {}) {
  const { k: kit = k, P } = sc;
  const cradle = { x: x - 12, y: y - 9, w: 24, d: 18, r: 2 };
  sc.slab(`${name}.cradle`, cradle, 0, 5, { extra: sc.D([sc.at([cradle.x + 3, cradle.y + 3, 5]), sc.at([cradle.x + cradle.w - 3, cradle.y + cradle.d - 3, 5])], { size: 0.45 }) });
  const bodyPlan = { x: x - 9, y: y - 1.5, w: 18, d: 3, r: 1 };
  const face = kit.sideMatrix([bodyPlan.x + 1.5, bodyPlan.y + bodyPlan.d], 8, P, "left");
  const screen = `<g data-screen="${name}"><path class="screen" transform="${face}" d="M0 0H15V${-(height - 6)}H0Z"/><path class="iso-line" data-tone="faint" transform="${face}" d="M0 0H15V${-(height - 6)}H0Z"/></g>`;
  const speaker = sc.L(kit.lineOnTop([bodyPlan.x + 7, bodyPlan.y + bodyPlan.d], [bodyPlan.x + 11, bodyPlan.y + bodyPlan.d], 5 + height - 2.4, P), { tone: "faint", free: true });
  sc.slab(`${name}.body`, bodyPlan, 5, height, { tone: "hi", crease: "lo", steps: 3, bevel: 0.5, extra: screen + speaker, bias: 0.2 });
}

/// A platter of rows: a knurled drum whose bands are the stored rows; `data-row` rings light
/// when a row is written.
export function platter(sc, name, [x, y], z, { r = 7, h = 9, rows = 3 } = {}) {
  const rings = Array.from({ length: rows }, (_, i) => `<g data-row="${i}">${sc.L(k.sideArc(x, y, r, z + 1.5 + (i * (h - 3)) / Math.max(1, rows - 1), sc.P, 24), { tone: "faint" })}</g>`).join("");
  const top = sc.L(k.ring(x, y, r - 2, z + h, sc.P, 32), { tone: "lo" });
  const knurl = sc.L(k.knurl(x, y, r, z + 1.5, z + h - 1.5, Math.round(r * 5), sc.P, 0.3), { tone: "faint" });
  sc.cyl(name, x, y, r, z, h, { steps: 36, bevel: 0.6, extra: rings + top + knurl });
}

/// A gear: a disc with teeth drawn as radial ticks that the page rebuilds at the story's angle.
/// Returns the pure function the page needs, as source.
export function gear(sc, name, [x, y], z, { r = 6, h = 2.5, teeth = 12 } = {}) {
  const hub = sc.L(k.ring(x, y, 1.4, z + h, sc.P, 12), { tone: "lo" });
  const teethNow = gearTeeth(x, y, r, teeth, z + h, 0, sc.P);
  sc.cyl(name, x, y, r, z, h, { tone: "hi", crease: "lo", steps: 36, bevel: 0.4, extra: `<path data-gear="${name}" class="iso-line" data-tone="mid" d="${teethNow}"/>` + hub });
  return { x, y, r, teeth, z: z + h };
}

/// Teeth as short radial marks round the rim, rotated by `angle`. Shared with the page.
export function gearTeeth(cx, cy, r, teeth, z, angle, P) {
  const out = [];
  for (let i = 0; i < teeth; i++) {
    const a = angle + (i / teeth) * Math.PI * 2;
    const [sx, sy] = [Math.sin(a), -Math.cos(a)];
    out.push(k.lineOnTop([cx + sx * (r - 2.2), cy + sy * (r - 2.2)], [cx + sx * (r - 0.4), cy + sy * (r - 0.4)], z, P));
  }
  return out.join("");
}

/// An Edge Function booth: a box with a small gear on its roof and a lamp.
export function booth(sc, name, plan, { h = 12 } = {}) {
  const inset = sc.L(k.planOutline(k.insetPlan(plan, 2), h, sc.P, 4), { tone: "faint" });
  const screws = sc.D(k.corners(plan, 3).map(([x, y]) => sc.at([x, y, h])), { size: 0.45 });
  sc.slab(name, plan, 0, h, { extra: inset + screws });
  return gear(sc, `${name}.gear`, [plan.x + plan.w / 2, plan.y + plan.d / 2], h, { r: 4.5, h: 2, teeth: 10 });
}

/// The screen polyline of a 3D route, with arc-length tables, for beads in the page.
export function routeTable(route, P) {
  return route.map((p) => k.iso(p, P));
}

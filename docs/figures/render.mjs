// Renders a figure's story to an MP4: one frame per 1/30 s of story time, 1920×1080, the card
// centred on the page's own background.
//
//   node docs/figures/render.mjs docs/figures/last-spot/index.html out/last-spot.mp4 [--fps 30] [--hold 1.5]
//
// Needs Playwright (its Chromium) and ffmpeg on the PATH. The page exposes window.__story.seek(t)
// and window.__story.loop, so every frame is placed exactly; nothing depends on wall-clock timing.
// --hold adds that many seconds of the final frame at the end, so a cut has somewhere to land.

import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const args = process.argv.slice(2);
const flag = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const [input, output] = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--")));
if (!input || !output) { console.error("usage: node render.mjs <page.html> <out.mp4> [--fps 30] [--hold 1.5] [--width 1920] [--height 1080]"); process.exit(1); }
const fps = Number(flag("--fps", 30));
const hold = Number(flag("--hold", 1.5));
const width = Number(flag("--width", 1920));
const height = Number(flag("--height", 1080));

const require = createRequire(import.meta.url);
const playwrightPath = process.env.PLAYWRIGHT_PATH ?? "playwright";
const { chromium } = require(playwrightPath);

const frames = mkdtempSync(join(tmpdir(), "figure-frames-"));
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
try {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(resolve(input)).href, { waitUntil: "load" });
  // Centre the card and drop the legend: the clip is the card alone, at the largest size that fits.
  await page.addStyleTag({ content: `
    html,body{margin:0;height:100%;overflow:hidden}
    body{display:flex;align-items:center;justify-content:center}
    .iso-page{width:${Math.min(width - 160, Math.round((height - 80) * 650 / 485))}px;max-width:none;padding:0;margin:0}
    .iso-legend{display:none}
    .iso-stage{outline:none}
  ` });
  await page.waitForFunction(() => window.__story && typeof window.__story.seek === "function");
  const loop = await page.evaluate(() => window.__story.loop);
  const total = Math.round(loop * fps) + Math.round(hold * fps);
  for (let i = 0; i < total; i++) {
    const t = Math.min(i / fps, loop - 1 / fps);
    await page.evaluate((time) => window.__story.seek(time), t);
    await page.screenshot({ path: join(frames, `f-${String(i).padStart(5, "0")}.png`), type: "png" });
    if (i % fps === 0) process.stdout.write(`\r${(i / fps).toFixed(0)} s of ${(total / fps).toFixed(1)} s`);
  }
  process.stdout.write("\n");
} finally {
  await browser.close();
}

mkdirSync(dirname(resolve(output)), { recursive: true });
const ffmpeg = spawnSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", String(fps), "-i", join(frames, "f-%05d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-movflags", "+faststart", resolve(output)], { stdio: "inherit" });
rmSync(frames, { recursive: true, force: true });
if (ffmpeg.status !== 0) process.exit(ffmpeg.status ?? 1);
console.log("wrote", output);

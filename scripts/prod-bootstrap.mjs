#!/usr/bin/env node
// One-shot production setup. Pauses the outdated courtly-prod project (its data stays recoverable
// from the dashboard), creates a fresh one, writes the new ref and publishable key into the app, the
// workflow and the README, deploys the backend to it, creates the App Review account, and copies the
// sign-in settings (email templates, SMTP, Apple, Google, site URL) from dev. Safe to run twice: a
// fresh project named NEW_NAME is reused, and every deploy step is idempotent.
//
//   SUPABASE_ACCESS_TOKEN=sbp_… REVIEWER_PASSWORD=12345678 node scripts/prod-bootstrap.mjs
//
// Optional: NEW_NAME (default courtly-prod), OLD_REF (default jrlocgfyskutnusscenf), REGION (us-east-1),
// DEMO_PASSWORD (also seeds the four demo players, so App Review has a world to look at).
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
if (!TOKEN) throw new Error("SUPABASE_ACCESS_TOKEN is required");
if (!/^\d{8}$/.test(process.env.REVIEWER_PASSWORD ?? "")) throw new Error("REVIEWER_PASSWORD must be eight digits");
const DEV_REF = "letuvtazmtjkvivattfy";
const OLD_REF = process.env.OLD_REF ?? "jrlocgfyskutnusscenf";
const NEW_NAME = process.env.NEW_NAME ?? "courtly-prod";
const REGION = process.env.REGION ?? "us-east-1";
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function api(method, route, body) {
  const res = await fetch(`https://api.supabase.com/v1${route}`, {
    method,
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${route} → ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// 1. The old project is paused, never deleted: everything in it can be restored from the dashboard.
const projects = await api("GET", "/projects");
const old = projects.find((p) => p.id === OLD_REF);
if (old && old.status === "ACTIVE_HEALTHY") {
  console.log(`pause   ${old.name} (${OLD_REF}); restorable from the dashboard`);
  await api("POST", `/projects/${OLD_REF}/pause`);
} else {
  console.log(`pause   ${OLD_REF} is already ${old?.status ?? "gone"}`);
}

// 2. A fresh project: the one PROD_REF names, else one by NEW_NAME (other than the old one), else created.
// The listing can lag a project made in the dashboard moments ago, which is what PROD_REF is for.
let fresh = process.env.PROD_REF ? { id: process.env.PROD_REF } : projects.find((p) => p.name === NEW_NAME && p.id !== OLD_REF);
if (!fresh) {
  // The token may not list organizations; every project carries its organization's id.
  const orgID = old?.organization_id ?? projects[0]?.organization_id ?? (await api("GET", "/organizations"))[0]?.id;
  if (!orgID) throw new Error("no organization found to create the project in");
  const dbPass = crypto.randomBytes(24).toString("base64url");
  fs.writeFileSync(path.join(ROOT, ".prod-db-password"), `${dbPass}\n`, { mode: 0o600 });
  console.log(`create  ${NEW_NAME} in organization ${orgID} (${REGION}); database password saved to .prod-db-password (gitignored)`);
  fresh = await api("POST", "/projects", { organization_id: orgID, name: NEW_NAME, db_pass: dbPass, region: REGION });
}
const REF = fresh.id;
for (let i = 0; ; i++) {
  const p = await api("GET", `/projects/${REF}`);
  if (p.status === "ACTIVE_HEALTHY") break;
  if (i >= 60) throw new Error(`project ${REF} is still ${p.status} after ten minutes`);
  console.log(`wait    ${REF} is ${p.status}`);
  await sleep(10000);
}
console.log(`project ${REF} ready`);

// 3. The publishable key, written into the app, the workflow and the README.
const keys = await api("GET", `/projects/${REF}/api-keys?reveal=true`);
let pub = keys.find((k) => k.type === "publishable")?.api_key;
if (!pub) {
  const made = await api("POST", `/projects/${REF}/api-keys?reveal=true`, { type: "publishable", name: "default", description: "Courtly iOS" });
  pub = made.api_key;
}
if (!pub?.startsWith("sb_publishable_")) throw new Error("the new project has no publishable key");
const edit = (file, from, to) => {
  const p = path.join(ROOT, file);
  const before = fs.readFileSync(p, "utf8");
  const after = before.replace(from, to);
  if (after === before) { console.log(`skip    ${file} (already current)`); return; }
  fs.writeFileSync(p, after);
  console.log(`edit    ${file}`);
};
edit(
  "ios/Courtly/Config/AppConfig.swift",
  /https:\/\/[a-z]{20}\.supabase\.co"\)!\n(\s*)static let supabaseAnonKey = "sb_publishable_[A-Za-z0-9_-]+"\n(\s*)static let apnsEnvironment = "production"/,
  `https://${REF}.supabase.co")!\n$1static let supabaseAnonKey = "${pub}"\n$2static let apnsEnvironment = "production"`,
);
edit(".github/workflows/backend.yml", new RegExp(OLD_REF, "g"), REF);
edit("README.md", new RegExp(OLD_REF, "g"), REF);

// 4. The backend, the App Review account and, with DEMO_PASSWORD, the demo world.
const steps = ["check", "migrate", "seed", "settings", "auth", "secrets", "functions", "test", "reviewer", ...(process.env.DEMO_PASSWORD ? ["demo"] : []), "status"];
console.log(`deploy  ${steps.join(" ")}`);
execFileSync("node", [path.join(ROOT, "scripts/supabase-deploy.mjs"), ...steps], {
  stdio: "inherit",
  env: {
    ...process.env,
    SUPABASE_PROJECT_REF: REF,
    APNS_BUNDLE_ID: "com.charanjarugula.courtly",
    APPLE_CLIENT_ID: "com.charanjarugula.courtly",
    ADMIN_EMAIL: "courtly.support@gmail.com",
  },
});

// 5. Sign-in settings copied from dev. The deploy's auth step set the templates; this adds SMTP,
// the providers and the site URL, which live only in the dashboard.
const dev = await api("GET", `/projects/${DEV_REF}/config/auth`);
const copy = {};
for (const k of [
  "site_url", "mailer_otp_length", "mailer_otp_exp",
  "mailer_subjects_magic_link", "mailer_subjects_confirmation", "mailer_templates_magic_link_content", "mailer_templates_confirmation_content",
  "smtp_host", "smtp_port", "smtp_user", "smtp_pass", "smtp_admin_email", "smtp_sender_name", "smtp_max_frequency", "rate_limit_email_sent",
  "external_apple_enabled", "external_apple_client_id", "external_google_enabled", "external_google_client_id",
]) {
  if (dev[k] !== null && dev[k] !== undefined && dev[k] !== "") copy[k] = dev[k];
}
await api("PATCH", `/projects/${REF}/config/auth`, copy);
console.log(`auth    copied from dev: ${Object.keys(copy).map((k) => (k === "smtp_pass" ? "smtp_pass(set)" : k)).join(", ")}`);
if (!copy.smtp_pass) console.log("auth    dev had no SMTP password readable; set it on the new project under Authentication → SMTP");

console.log(`\nDone. Prod is ${REF}. Commit the edited files (AppConfig.swift, backend.yml, README.md) so Release builds and the workflow use it.`);

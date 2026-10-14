#!/usr/bin/env node
// Deploys the Courtly backend to a Supabase project through the Management API.
//
// Needs SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF. No database password: migrations
// run through the SQL endpoint, functions through the deploy endpoint.
//
//   node scripts/supabase-deploy.mjs check migrate seed settings functions test
//
// Steps run in the order given. Secrets for Edge Functions come from the environment and
// are only sent when present (see SECRET_NAMES). The optional "reviewer" step creates or
// updates the App Review account (reviewer@courtly.app) with REVIEWER_PASSWORD, a six-digit
// code the reviewer types where the app asks for the email code.

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const API = "https://api.supabase.com/v1";
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "supabase");
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
const REF = process.env.SUPABASE_PROJECT_REF;

const FUNCTIONS = {
  "send-push": { verifyJwt: false }, // called by the database webhook, authenticated by a shared secret
  "delete-account": { verifyJwt: true },
  "apple-token-exchange": { verifyJwt: true },
};

const SECRET_NAMES = [
  "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_PRIVATE_KEY", "APNS_BUNDLE_ID",
  "APPLE_SIWA_KEY_ID", "APPLE_SIWA_PRIVATE_KEY", "APPLE_TEAM_ID", "APPLE_CLIENT_ID",
  "WEBHOOK_SECRET", "ADMIN_EMAIL",
];

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

async function api(method, route, body, headers = {}) {
  const init = { method, headers: { Authorization: `Bearer ${TOKEN}`, ...headers } };
  if (body !== undefined) {
    if (body instanceof FormData) {
      init.body = body;
    } else {
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
  }
  const response = await fetch(`${API}${route}`, init);
  const text = await response.text();
  let data = text;
  try { data = JSON.parse(text); } catch { /* plain text */ }
  if (!response.ok) {
    const detail = typeof data === "string" ? data : (data.message ?? JSON.stringify(data));
    throw new Error(`${method} ${route} → ${response.status}: ${detail}`);
  }
  return data;
}

const sql = (query) => api("POST", `/projects/${REF}/database/query`, { query });

async function sqlFiles(dir) {
  const names = (await readdir(dir)).filter((n) => n.endsWith(".sql")).sort();
  return Promise.all(names.map(async (name) => ({ name, text: await readFile(path.join(dir, name), "utf8") })));
}

const steps = {
  async check() {
    const project = await api("GET", `/projects/${REF}`);
    console.log(`project ${project.name} (${project.region}) status=${project.status}`);
    if (project.status && project.status !== "ACTIVE_HEALTHY") {
      fail(`project is ${project.status}; open it in the dashboard to resume it`);
    }
  },

  async migrate() {
    await sql(`
      create schema if not exists private;
      revoke all on schema private from public, anon, authenticated;
      create table if not exists private.app_migrations (
        name text primary key,
        applied_at timestamptz not null default now()
      );
    `);
    const applied = new Set((await sql(`select name from private.app_migrations`)).map((r) => r.name));
    for (const file of await sqlFiles(path.join(ROOT, "migrations"))) {
      if (applied.has(file.name)) { console.log(`skip    ${file.name}`); continue; }
      console.log(`apply   ${file.name}`);
      const literal = file.name.replace(/'/g, "''");
      await sql(`${file.text}\n\ninsert into private.app_migrations (name) values ('${literal}');`);
    }
  },

  async seed() {
    for (const file of await sqlFiles(path.join(ROOT, "seed"))) {
      console.log(`seed    ${file.name}`);
      await sql(file.text);
    }
  },

  async settings() {
    const webhookSecret = process.env.WEBHOOK_SECRET || crypto.randomBytes(32).toString("hex");
    process.env.WEBHOOK_SECRET = webhookSecret;
    const functionsUrl = `https://${REF}.supabase.co/functions/v1`;
    await sql(`
      insert into private.settings (key, value) values
        ('functions_url', '${functionsUrl}'),
        ('webhook_secret', '${webhookSecret}')
      on conflict (key) do update set value = excluded.value;
    `);
    console.log(`settings functions_url=${functionsUrl} webhook_secret=(set)`);
  },

  async secrets() {
    const present = SECRET_NAMES.filter((name) => process.env[name]).map((name) => ({ name, value: process.env[name] }));
    if (present.length === 0) { console.log("secrets none provided"); return; }
    await api("POST", `/projects/${REF}/secrets`, present);
    console.log(`secrets set ${present.map((s) => s.name).join(", ")}`);
  },

  async functions() {
    const dir = path.join(ROOT, "functions");
    for (const slug of await readdir(dir)) {
      const config = FUNCTIONS[slug];
      if (!config) { console.log(`skip    functions/${slug} (not in FUNCTIONS)`); continue; }
      const form = new FormData();
      const files = await walk(path.join(dir, slug));
      for (const file of files) {
        const relative = path.posix.join("supabase", "functions", slug, path.relative(path.join(dir, slug), file).split(path.sep).join("/"));
        form.append("file", new Blob([await readFile(file)]), relative);
      }
      form.append("metadata", JSON.stringify({
        name: slug,
        entrypoint_path: `supabase/functions/${slug}/index.ts`,
        verify_jwt: config.verifyJwt,
      }));
      await api("POST", `/projects/${REF}/functions/deploy?slug=${slug}`, form);
      console.log(`deploy  ${slug} (${files.length} files, verify_jwt=${config.verifyJwt})`);
    }
  },

  async reviewer() {
    const password = process.env.REVIEWER_PASSWORD;
    if (!password) { console.log("reviewer REVIEWER_PASSWORD not set, skipped"); return; }
    if (!/^\d{6}$/.test(password)) fail("REVIEWER_PASSWORD must be exactly six digits; the app enters it as a code");
    const literal = password.replace(/'/g, "''");
    await sql(`
      do $body$
      declare v_id uuid; v_email text := 'reviewer@courtly.app';
      begin
        select id into v_id from auth.users where email = v_email;
        if v_id is null then
          v_id := gen_random_uuid();
          insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data,
                                  raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change, is_sso_user)
          values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
                  extensions.crypt('${literal}', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}'::jsonb,
                  '{}'::jsonb, now(), now(), '', '', '', '', false);
          insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
          values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
        else
          update auth.users set encrypted_password = extensions.crypt('${literal}', extensions.gen_salt('bf')), updated_at = now() where id = v_id;
        end if;
        update public.profiles set first_name = 'App', last_name = 'Reviewer', birthday = '1990-01-01', level = 'intermediate', formats = '{casual}',
          zip = '33414', area_label = 'Wellington, FL',
          home_point = extensions.st_setsrid(extensions.st_makepoint(-80.2416, 26.6618), 4326)::extensions.geography,
          radius_mi = 15, availability_mask = 2097151, onboarding_completed_at = coalesce(onboarding_completed_at, now()), coach_marks_done = true
        where id = v_id;
      end $body$;
    `);
    console.log("reviewer reviewer@courtly.app ready (password set, profile onboarded)");
  },

  async test() {
    const text = await readFile(path.join(ROOT, "tests", "smoke.sql"), "utf8");
    try {
      await sql(text);
      fail("smoke test finished without raising SMOKE_OK; it must end by raising it so nothing persists");
    } catch (error) {
      if (!String(error.message).includes("SMOKE_OK")) throw error;
      console.log("test    smoke passed");
    }
  },
};

async function walk(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...await walk(full));
    else out.push(full);
  }
  return out;
}

async function main() {
  if (!TOKEN || !REF) fail("SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF are required");
  const requested = process.argv.slice(2);
  if (requested.length === 0) fail(`no steps given; choose from ${Object.keys(steps).join(", ")}`);
  for (const name of requested) {
    if (!steps[name]) fail(`unknown step "${name}"`);
    console.log(`== ${name}`);
    await steps[name]();
  }
}

main().catch((error) => fail(error.message));

// Emails a new report to the support inbox so a person sees it the same day.
// Called by the database with { report_id }; authenticated by x-webhook-secret.

import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";
import { webhookSecretMatches } from "../_shared/webhook.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!(await webhookSecretMatches(req))) return json({ error: "forbidden" }, 403);

  const to = Deno.env.get("ADMIN_EMAIL");
  const user = Deno.env.get("REPORT_SMTP_USER");
  const pass = Deno.env.get("REPORT_SMTP_PASS");
  if (!to || !user || !pass) return json({ skipped: "email not configured" });

  const { report_id: id } = await req.json();
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: report } = await db.from("reports").select("*").eq("id", id).maybeSingle();
  if (!report) return json({ error: "not_found" }, 404);
  const { data: people } = await db.from("profiles")
    .select("id, first_name, last_name, no_shows")
    .in("id", [report.reporter_id, report.reported_id]);
  const name = (uid: string) => {
    const p = people?.find((x) => x.id === uid);
    return p ? `${p.first_name} ${p.last_name}`.trim() : uid;
  };
  const { count } = await db.from("reports").select("id", { count: "exact", head: true }).eq("reported_id", report.reported_id);

  const lines = [
    `Reason: ${String(report.reason).replaceAll("_", " ")}${report.auto ? " (automatic, from a no-show answer)" : ""}`,
    `Reported: ${name(report.reported_id)} (${report.reported_id})`,
    `Reported by: ${name(report.reporter_id)}`,
    `Reports against this player so far: ${count ?? 1}`,
    report.message_body ? `\nMessage reported:\n"${report.message_body}"` : "",
    report.details ? `\nDetails from the reporter:\n${report.details}` : "",
    report.also_blocked ? "\nThe reporter also blocked them." : "",
    `\nTo suspend this player, run in the Supabase SQL editor:\nselect private.suspend_user('${report.reported_id}', true);`,
    `\nReport ${report.id}, filed ${new Date(report.created_at).toUTCString()}`,
  ].filter(Boolean);

  // Port 465: Supabase functions can't reach SMTP on 25 or 587.
  const transport = nodemailer.createTransport({
    host: Deno.env.get("REPORT_SMTP_HOST") ?? "smtp.gmail.com", port: 465, secure: true, auth: { user, pass },
  });
  try {
    await transport.sendMail({
      from: `Courtly reports <${user}>`,
      to,
      subject: `Courtly report: ${name(report.reported_id)} · ${String(report.reason).replaceAll("_", " ")}`,
      text: lines.join("\n"),
    });
  } catch (error) {
    return json({ error: "send_failed", detail: String(error) }, 502);
  }
  return json({ sent: true });
});

// Delivers one notifications row to the player's devices through APNs.
// Called by the database webhook with { notification_id }; authenticated by x-webhook-secret.

import { createClient } from "npm:@supabase/supabase-js@2";
import { signES256 } from "../_shared/apple-jwt.ts";
import { webhookSecretMatches } from "../_shared/webhook.ts";

const IN_APP_ONLY = new Set(["friend_added", "friend_accepted"]);

let cachedToken: { value: string; issuedAt: number } | null = null;

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.issuedAt < 50 * 60) return cachedToken.value;
  const value = await signES256(
    Deno.env.get("APNS_PRIVATE_KEY")!,
    { alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") },
    { iss: Deno.env.get("APNS_TEAM_ID"), iat: now },
  );
  cachedToken = { value, issuedAt: now };
  return value;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!(await webhookSecretMatches(req))) return json({ error: "forbidden" }, 403);

  const { notification_id: id } = await req.json();
  if (!id) return json({ error: "notification_id required" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: n, error } = await supabase.from("notifications").select("*").eq("id", id).maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!n || n.pushed_at) return json({ skipped: true });
  if (IN_APP_ONLY.has(n.kind)) {
    await supabase.from("notifications").update({ pushed_at: new Date().toISOString(), push_status: "in_app_only" }).eq("id", id);
    return json({ skipped: "in_app_only" });
  }

  const { data: devices, error: deviceError } = await supabase.from("device_tokens").select("token, environment").eq("user_id", n.user_id);
  // A lookup that failed is not "no devices": the notification stays pending for the retry sweep.
  if (deviceError) return json({ error: deviceError.message }, 500);
  const { data: badge } = await supabase.rpc("badge_count", { p_user: n.user_id });

  // Phones that already have this push (an earlier attempt that partly failed) are not sent it again.
  const delivered: string[] = Array.isArray(n.push_delivered) ? n.push_delivered : [];
  const pending = (devices ?? []).filter((d) => !delivered.includes(d.token));
  const results: Record<string, string> = {};
  if (pending.length > 0 && Deno.env.get("APNS_PRIVATE_KEY")) {
    const token = await providerToken();
    const payload = {
      aps: {
        alert: { title: n.title, body: n.body },
        badge: typeof badge === "number" ? badge : 0,
        sound: "default",
        ...(n.collapse_id ? { "thread-id": n.collapse_id } : {}),
      },
      deep_link: n.deep_link,
      kind: n.kind,
      data: n.data,
    };
    for (const device of pending) {
      const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const headers: Record<string, string> = {
        authorization: `bearer ${token}`,
        "apns-topic": Deno.env.get("APNS_BUNDLE_ID")!,
        "apns-push-type": "alert",
        "apns-priority": "10",
      };
      if (n.collapse_id) headers["apns-collapse-id"] = n.collapse_id;
      try {
        const response = await fetch(`https://${host}/3/device/${device.token}`, {
          method: "POST",
          headers,
          body: JSON.stringify(payload),
        });
        const text = await response.text();
        results[device.token.slice(0, 8)] = `${response.status} ${text}`.trim();
        if (response.status === 200) delivered.push(device.token);
        if (response.status === 410 || text.includes("BadDeviceToken") || text.includes("Unregistered")) {
          await supabase.from("device_tokens").delete().eq("token", device.token);
          delivered.push(device.token);   // gone for good: nothing left to retry for this phone
        }
      } catch (err) {
        results[device.token.slice(0, 8)] = `error ${(err as Error).message}`;
      }
    }
  }

  // Finished once every current phone has it (or there is none); otherwise the sweep comes back for the rest.
  const everyPhoneHasIt = (devices ?? []).every((d) => delivered.includes(d.token));
  const status = !devices?.length
    ? "no_devices"
    : !Deno.env.get("APNS_PRIVATE_KEY")
    ? "apns_not_configured"
    : JSON.stringify(results).slice(0, 500);
  await supabase.from("notifications").update({
    pushed_at: everyPhoneHasIt ? new Date().toISOString() : null,
    push_status: status,
    push_attempts: (n.push_attempts ?? 0) + 1,
    push_delivered: delivered,
  }).eq("id", id);

  return json({ delivered: everyPhoneHasIt, results });
});

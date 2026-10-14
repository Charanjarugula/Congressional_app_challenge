// Exchanges a Sign in with Apple authorization code for a refresh token and stores it,
// so the account can be revoked at Apple when the player deletes their account.
// Called right after sign-in with the user's JWT and { authorization_code }.

import { createClient } from "npm:@supabase/supabase-js@2";
import { appleClientSecret } from "../_shared/apple-jwt.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const authorization = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "not_signed_in" }, 401);

  const { authorization_code: code } = await req.json();
  if (!code) return json({ error: "authorization_code required" }, 400);
  if (!Deno.env.get("APPLE_SIWA_PRIVATE_KEY")) return json({ error: "apple_not_configured" }, 503);

  const form = new URLSearchParams({
    client_id: Deno.env.get("APPLE_CLIENT_ID")!,
    client_secret: await appleClientSecret(),
    code,
    grant_type: "authorization_code",
  });
  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  const data = await response.json();
  if (!response.ok || !data.refresh_token) return json({ error: "apple_exchange_failed", detail: data }, 502);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.rpc("internal_store_apple_token", { p_user: user.id, p_refresh_token: data.refresh_token });
  if (error) return json({ error: error.message }, 500);
  return json({ stored: true });
});

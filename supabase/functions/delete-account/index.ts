// In-app account deletion. Cancels and leaves future hits, removes personal data, revokes the
// Sign in with Apple token, deletes avatars, then deletes the auth user.
// Called with the user's JWT. Body: { mode?: "full" | "underage" }.

import { createClient } from "npm:@supabase/supabase-js@2";
import { appleClientSecret } from "./apple-jwt.ts";

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

  let mode = "full";
  try {
    const body = await req.json();
    if (body?.mode === "underage") mode = "underage";
  } catch { /* no body */ }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const steps: Record<string, string> = {};

  // Apple requires revoking the token when the account is deleted; a missing token must not block deletion.
  try {
    const { data: refreshToken } = await admin.rpc("internal_apple_refresh_token", { p_user: user.id });
    if (refreshToken && Deno.env.get("APPLE_SIWA_PRIVATE_KEY")) {
      const form = new URLSearchParams({
        client_id: Deno.env.get("APPLE_CLIENT_ID")!,
        client_secret: await appleClientSecret(),
        token: refreshToken,
        token_type_hint: "refresh_token",
      });
      const response = await fetch("https://appleid.apple.com/auth/revoke", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form,
      });
      steps.apple = `revoke ${response.status}`;
    } else {
      steps.apple = "no token";
    }
  } catch (err) {
    steps.apple = `error ${(err as Error).message}`;
  }

  const { error: dbError } = await admin.rpc("internal_delete_account", { p_user: user.id, p_mode: mode });
  if (dbError) return json({ error: dbError.message, steps }, 500);
  steps.database = "done";

  try {
    const { data: files } = await admin.storage.from("avatars").list(user.id);
    if (files && files.length > 0) {
      await admin.storage.from("avatars").remove(files.map((f) => `${user.id}/${f.name}`));
    }
    steps.storage = `removed ${files?.length ?? 0}`;
  } catch (err) {
    steps.storage = `error ${(err as Error).message}`;
  }

  const { error: authError } = await admin.auth.admin.deleteUser(user.id);
  if (authError) return json({ error: authError.message, steps }, 500);
  steps.auth = "deleted";

  return json({ deleted: true, steps });
});

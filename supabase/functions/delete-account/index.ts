// In-app account deletion. Cancels and leaves future hits, removes personal data, revokes the
// Sign in with Apple token, deletes avatars, then deletes the auth user.
// Called with the user's JWT. Body: { mode?: "full" | "underage" }.

import { createClient } from "npm:@supabase/supabase-js@2";
import { appleClientSecret } from "../_shared/apple-jwt.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  // The caller's token is checked with the service-role client, so the function does not depend on
  // which anon key the runtime was handed; the gateway has already verified the JWT's signature.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = token ? await admin.auth.getUser(token) : { data: { user: null } };
  if (!user) return json({ error: "not_signed_in" }, 401);

  let mode = "full";
  try {
    const body = await req.json();
    if (body?.mode === "underage") mode = "underage";
  } catch { /* no body */ }

  const steps: Record<string, string> = {};
  const tryAgain = (error: string, message: string, status: number) => json({ error, message, steps }, status);

  // Apple requires revoking the token when the account is deleted. A token Apple no longer recognises
  // (400) is fine; Apple being unreachable is not: nothing is deleted yet, and the app says to try again.
  // Without the Apple keys configured there is nothing to revoke with, and deletion must still work.
  const { data: refreshToken, error: tokenError } = await admin.rpc("internal_apple_refresh_token", { p_user: user.id });
  if (tokenError) return tryAgain("apple_token_lookup", tokenError.message, 500);
  if (refreshToken && Deno.env.get("APPLE_SIWA_PRIVATE_KEY")) {
    let status = 0;
    try {
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
      status = response.status;
    } catch {
      status = 0;
    }
    if (!(status >= 200 && status < 300) && status !== 400) {
      return tryAgain("apple_revoke_failed", "Apple couldn’t be reached to revoke your sign-in. Try again in a few minutes.", 503);
    }
    steps.apple = `revoke ${status}`;
  } else {
    steps.apple = refreshToken ? "keys not configured" : "no token";
  }

  // Photos go before the rows, so a storage failure leaves an account that still works and can retry.
  const { data: files, error: listError } = await admin.storage.from("avatars").list(user.id);
  if (listError) return tryAgain("storage_list_failed", listError.message, 500);
  if (files && files.length > 0) {
    const { error: removeError } = await admin.storage.from("avatars").remove(files.map((f) => `${user.id}/${f.name}`));
    if (removeError) return tryAgain("storage_remove_failed", removeError.message, 500);
  }
  steps.storage = `removed ${files?.length ?? 0}`;

  const { error: dbError } = await admin.rpc("internal_delete_account", { p_user: user.id, p_mode: mode });
  if (dbError) return tryAgain("database", dbError.message, 500);
  steps.database = "done";

  const { error: authError } = await admin.auth.admin.deleteUser(user.id);
  if (authError) return json({ error: authError.message, steps }, 500);
  steps.auth = "deleted";

  return json({ deleted: true, steps });
});

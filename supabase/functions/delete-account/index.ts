// In-app account deletion. Cancels and leaves future hits, removes personal data, revokes the
// Sign in with Apple token, deletes avatars, then deletes the auth user.
// Called with the user's JWT. Body: { mode?: "full" | "underage" }.

import { createClient } from "npm:@supabase/supabase-js@2";
import { appleClientSecret } from "../_shared/apple-jwt.ts";
import { json } from "../_shared/http.ts";

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

  // Apple requires revoking the token when the account is deleted. Apple being unreachable (network
  // or 5xx) stops here: nothing is deleted yet, and the app says to try again. Apple answering
  // invalid_grant means the token is already dead, which is fine. Anything else (our key or client
  // id wrong) is logged loudly but doesn't trap the player in an account they asked to delete.
  const { data: refreshToken, error: tokenError } = await admin.rpc("internal_apple_refresh_token", { p_user: user.id });
  if (tokenError) return tryAgain("apple_token_lookup", tokenError.message, 500);
  if (refreshToken && Deno.env.get("APPLE_SIWA_PRIVATE_KEY")) {
    let clientSecret: string | null = null;
    try {
      clientSecret = await appleClientSecret();
    } catch (error) {
      console.error("apple revoke: client secret could not be made; check APPLE_SIWA_* secrets", error);
      steps.apple = "config error: client secret";
    }
    if (clientSecret) {
      let status = 0;
      let appleError = "";
      try {
        const response = await fetch("https://appleid.apple.com/auth/revoke", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: Deno.env.get("APPLE_CLIENT_ID")!,
            client_secret: clientSecret,
            token: refreshToken,
            token_type_hint: "refresh_token",
          }),
        });
        status = response.status;
        if (status === 400) appleError = String((await response.json().catch(() => ({})))?.error ?? "");
      } catch {
        status = 0;
      }
      if (status === 0 || status >= 500) {
        return tryAgain("apple_revoke_failed", "Apple couldn’t be reached to revoke your sign-in. Try again in a few minutes.", 503);
      }
      if (status === 400 && appleError !== "invalid_grant") {
        console.error(`apple revoke refused: ${appleError || "unknown"}; check APPLE_CLIENT_ID and the Sign in with Apple key`);
      }
      steps.apple = status === 400 ? `revoke 400 ${appleError || "unknown"}` : `revoke ${status}`;
    }
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

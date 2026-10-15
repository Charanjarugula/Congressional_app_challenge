// The database's calls to send-push and report-email carry a shared secret. It is compared in
// constant time (over SHA-256 digests, so lengths don't leak either); a missing secret never matches.
const encoder = new TextEncoder();

async function digest(value: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

export async function webhookSecretMatches(req: Request): Promise<boolean> {
  const expected = Deno.env.get("WEBHOOK_SECRET") ?? "";
  const given = req.headers.get("x-webhook-secret") ?? "";
  if (!expected || !given) return false;
  const [a, b] = await Promise.all([digest(given), digest(expected)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

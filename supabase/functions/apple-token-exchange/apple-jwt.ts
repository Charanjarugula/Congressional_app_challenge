// ES256 JWTs for Apple services (APNs provider tokens and Sign in with Apple client secrets).

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function signES256(
  privateKeyPem: string,
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const encoder = new TextEncoder();
  const signingInput =
    `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(claims)))}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

/** Client secret for Sign in with Apple token requests. Valid for 30 minutes. */
export function appleClientSecret(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return signES256(
    Deno.env.get("APPLE_SIWA_PRIVATE_KEY")!,
    { alg: "ES256", kid: Deno.env.get("APPLE_SIWA_KEY_ID") },
    {
      iss: Deno.env.get("APPLE_TEAM_ID"),
      iat: now,
      exp: now + 30 * 60,
      aud: "https://appleid.apple.com",
      sub: Deno.env.get("APPLE_CLIENT_ID"),
    },
  );
}

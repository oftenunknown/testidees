import type { Env } from "./types";

// Token-based APNs auth (ES256 JWT) with WebCrypto, so it runs on Workers.

export function base64url(bytes: ArrayBuffer | Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const b of data) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const raw = atob(b64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

let cachedToken: { value: string; issuedAt: number } | null = null;

export async function apnsJWT(env: Env, now = Date.now()): Promise<string> {
  // Apple accepts a token for up to an hour; refresh every 50 minutes.
  if (cachedToken && now - cachedToken.issuedAt < 50 * 60 * 1000) return cachedToken.value;
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) throw new Error("APNs is not configured");
  const header = base64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }));
  const key = await crypto.subtle.importKey("pkcs8", pemToPkcs8(env.APNS_KEY_P8), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  // WebCrypto returns the raw r||s signature that JWS ES256 expects.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  const token = `${header}.${claims}.${base64url(signature)}`;
  cachedToken = { value: token, issuedAt: now };
  return token;
}

export interface PushPayload {
  title: string;
  body: string;
  productID: string;
  url?: string;
  timeSensitive?: boolean;
}

/** Returns false when the token is dead and the watch should be dropped. */
export async function sendPush(env: Env, deviceToken: string, payload: PushPayload): Promise<boolean> {
  const host = env.APNS_PRODUCTION === "false" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const body = {
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      category: "PRICE_DROP",
      "thread-id": "price-drops",
      "interruption-level": payload.timeSensitive ? "time-sensitive" : "active",
    },
    productID: payload.productID,
    ...(payload.url ? { url: payload.url } : {}),
  };
  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJWT(env)}`,
      "apns-topic": env.APNS_BUNDLE_ID ?? "com.oftenunknown.snag",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (response.status === 410 || response.status === 400) {
    const reason = (await response.json().catch(() => ({}))) as { reason?: string };
    if (response.status === 410 || reason.reason === "BadDeviceToken") return false;
  }
  return true;
}

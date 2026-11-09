/**
 * Odyssey token server.
 *
 * Strava's OAuth has no PKCE, so turning an authorisation code into tokens
 * needs the app's client secret. For personal testing the iOS app can hold
 * the secret in its Keychain; to give the app to other people, deploy this
 * Worker and enter its URL in Settings instead. It only exchanges, refreshes
 * and revokes tokens — it never sees or stores activity data.
 */

export interface Env {
  STRAVA_CLIENT_ID?: string;
  STRAVA_CLIENT_SECRET?: string;
  /** Optional comma-separated athlete IDs allowed to sign in. */
  ALLOWED_ATHLETE_IDS?: string;
}

export const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
export const STRAVA_REVOKE_URL = "https://www.strava.com/oauth/revoke";

type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function error(message: string, status: number, code?: string): Response {
  return json(code ? { message, code } : { message }, status);
}

function stringField(body: unknown, name: string): string | null {
  if (typeof body !== "object" || body === null) return null;
  const value = (body as Record<string, unknown>)[name];
  return typeof value === "string" && /^[A-Za-z0-9._-]{8,200}$/.test(value) ? value : null;
}

export function allowedAthletes(env: Env): Set<string> | null {
  const raw = (env.ALLOWED_ATHLETE_IDS ?? "").trim();
  if (!raw) return null;
  return new Set(raw.split(",").map((s) => s.trim()).filter(Boolean));
}

async function revokeUpstream(token: string, env: Env, fetcher: Fetcher): Promise<Response> {
  const basic = btoa(`${env.STRAVA_CLIENT_ID}:${env.STRAVA_CLIENT_SECRET}`);
  return fetcher(STRAVA_REVOKE_URL, {
    method: "POST",
    headers: { authorization: `Basic ${basic}`, "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token, token_type_hint: "refresh_token" }).toString(),
  });
}

async function exchange(params: Record<string, string>, env: Env, fetcher: Fetcher, checkAthlete: boolean): Promise<Response> {
  const form = new URLSearchParams({
    client_id: env.STRAVA_CLIENT_ID ?? "",
    client_secret: env.STRAVA_CLIENT_SECRET ?? "",
    ...params,
  });
  const upstream = await fetcher(STRAVA_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: form.toString(),
  });
  const text = await upstream.text();
  if (!upstream.ok) {
    return new Response(text || JSON.stringify({ message: "Strava refused the request" }), {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  }
  const allowed = allowedAthletes(env);
  if (checkAthlete && allowed) {
    let athleteID: string | undefined;
    let refresh: string | undefined;
    try {
      const parsed = JSON.parse(text) as { athlete?: { id?: number | string }; refresh_token?: string };
      athleteID = parsed.athlete?.id === undefined ? undefined : String(parsed.athlete.id);
      refresh = parsed.refresh_token;
    } catch {
      return error("Unexpected response from Strava", 502);
    }
    if (!athleteID || !allowed.has(athleteID)) {
      // Don't leave a working grant behind for someone who isn't on the list.
      if (refresh) await revokeUpstream(refresh, env, fetcher).catch(() => undefined);
      return error("This Odyssey server isn't open to your Strava account.", 403, "athlete_not_allowed");
    }
  }
  return new Response(text, { status: 200, headers: { "content-type": "application/json" } });
}

export async function handle(request: Request, env: Env, fetcher: Fetcher = fetch): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/v1/health") {
    return json({ ok: true, configured: Boolean(env.STRAVA_CLIENT_ID && env.STRAVA_CLIENT_SECRET), restricted: allowedAthletes(env) !== null });
  }
  if (request.method !== "POST") return error("Not found", 404);
  if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET) return error("Token server is not configured", 501);
  const body: unknown = await request.json().catch(() => null);

  switch (url.pathname) {
    case "/v1/strava/token": {
      const code = stringField(body, "code");
      if (!code) return error("Missing code", 400);
      return exchange({ grant_type: "authorization_code", code }, env, fetcher, true);
    }
    case "/v1/strava/refresh": {
      const refresh = stringField(body, "refresh_token");
      if (!refresh) return error("Missing refresh_token", 400);
      return exchange({ grant_type: "refresh_token", refresh_token: refresh }, env, fetcher, false);
    }
    case "/v1/strava/revoke": {
      const token = stringField(body, "token");
      if (!token) return error("Missing token", 400);
      const upstream = await revokeUpstream(token, env, fetcher);
      return upstream.ok ? new Response(null, { status: 200 }) : error("Strava refused to revoke", upstream.status);
    }
    default:
      return error("Not found", 404);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env);
  },
} satisfies ExportedHandler<Env>;

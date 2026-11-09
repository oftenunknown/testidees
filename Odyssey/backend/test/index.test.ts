import { describe, expect, it } from "vitest";
import { handle, STRAVA_REVOKE_URL, STRAVA_TOKEN_URL, type Env } from "../src/index";

const env: Env = { STRAVA_CLIENT_ID: "12345", STRAVA_CLIENT_SECRET: "s3cret" };

type Call = { url: string; body: string; headers: Record<string, string> };

function fakeStrava(response: unknown, status = 200) {
  const calls: Call[] = [];
  const fetcher = async (url: string, init?: RequestInit) => {
    calls.push({ url, body: String(init?.body ?? ""), headers: (init?.headers ?? {}) as Record<string, string> });
    if (url === STRAVA_REVOKE_URL) return new Response(null, { status: 200 });
    return new Response(JSON.stringify(response), { status });
  };
  return { calls, fetcher };
}

function post(path: string, body: unknown): Request {
  return new Request(`https://odyssey.example.workers.dev${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

const tokens = { token_type: "Bearer", access_token: "a1", refresh_token: "r1abcdefgh", expires_at: 1793000000, athlete: { id: 4242, firstname: "Alex" } };

describe("token server", () => {
  it("exchanges a code with the secret it holds", async () => {
    const { calls, fetcher } = fakeStrava(tokens);
    const res = await handle(post("/v1/strava/token", { code: "abcdef123456" }), env, fetcher);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ access_token: "a1" });
    expect(calls[0]?.url).toBe(STRAVA_TOKEN_URL);
    const form = new URLSearchParams(calls[0]?.body);
    expect(form.get("client_id")).toBe("12345");
    expect(form.get("client_secret")).toBe("s3cret");
    expect(form.get("grant_type")).toBe("authorization_code");
    expect(form.get("code")).toBe("abcdef123456");
  });

  it("refreshes tokens", async () => {
    const { calls, fetcher } = fakeStrava({ access_token: "a2", refresh_token: "r2abcdefgh", expires_at: 1793021600 });
    const res = await handle(post("/v1/strava/refresh", { refresh_token: "r1abcdefgh" }), env, fetcher);
    expect(res.status).toBe(200);
    const form = new URLSearchParams(calls[0]?.body);
    expect(form.get("grant_type")).toBe("refresh_token");
    expect(form.get("refresh_token")).toBe("r1abcdefgh");
  });

  it("passes Strava errors through", async () => {
    const { fetcher } = fakeStrava({ message: "Bad Request", errors: [{ code: "invalid" }] }, 400);
    const res = await handle(post("/v1/strava/token", { code: "abcdef123456" }), env, fetcher);
    expect(res.status).toBe(400);
  });

  it("rejects bad input and missing configuration", async () => {
    const { fetcher } = fakeStrava(tokens);
    expect((await handle(post("/v1/strava/token", { code: "x" }), env, fetcher)).status).toBe(400);
    expect((await handle(post("/v1/strava/token", { code: "abcdef123456" }), {}, fetcher)).status).toBe(501);
    expect((await handle(new Request("https://x.dev/v1/strava/token"), env, fetcher)).status).toBe(404);
    const health = await handle(new Request("https://x.dev/v1/health"), env, fetcher);
    expect(await health.json()).toEqual({ ok: true, configured: true, restricted: false });
  });

  it("only lets listed athletes in, and revokes the rest", async () => {
    const { calls, fetcher } = fakeStrava(tokens);
    const ok = await handle(post("/v1/strava/token", { code: "abcdef123456" }), { ...env, ALLOWED_ATHLETE_IDS: "1, 4242" }, fetcher);
    expect(ok.status).toBe(200);
    const denied = await handle(post("/v1/strava/token", { code: "abcdef123456" }), { ...env, ALLOWED_ATHLETE_IDS: "1,2" }, fetcher);
    expect(denied.status).toBe(403);
    expect(((await denied.json()) as { code?: string }).code).toBe("athlete_not_allowed");
    const revoke = calls.find((c) => c.url === STRAVA_REVOKE_URL);
    expect(revoke).toBeDefined();
    expect(revoke?.headers.authorization).toBe(`Basic ${btoa("12345:s3cret")}`);
  });

  it("revokes on request", async () => {
    const { calls, fetcher } = fakeStrava({});
    const res = await handle(post("/v1/strava/revoke", { token: "r1abcdefgh" }), env, fetcher);
    expect(res.status).toBe(200);
    expect(new URLSearchParams(calls[0]?.body).get("token")).toBe("r1abcdefgh");
  });
});

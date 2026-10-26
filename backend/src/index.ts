import Anthropic from "@anthropic-ai/sdk";
import { alertText, evaluateAlert } from "./alerts";
import { sendPush } from "./apns";
import { generateGiftIdeas, GiftRefusalError, type GiftRequestBody } from "./gifts";
import { bestOffer, searchShopping } from "./offers";
import type { Env, Offer, Region, StoredWatch, WatchRegistration } from "./types";
import { isoDate, REGION_CURRENCY } from "./types";

const REGIONS: Region[] = ["us", "uk", "eu", "other"];
const OFFER_CACHE_SECONDS = 30 * 60;
const WATCHES_PER_RUN = 40;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

function deviceID(request: Request): string | null {
  const id = request.headers.get("X-Snag-Device");
  return id && /^[A-Za-z0-9-]{8,64}$/.test(id) ? id : null;
}

async function cachedOffers(env: Env, query: string, region: Region): Promise<Offer[]> {
  if (!env.SERPAPI_KEY) return [];
  const key = `offers:${region}:${query.toLowerCase().trim()}`;
  const cached = await env.SNAG.get<Offer[]>(key, "json");
  if (cached) return cached;
  const offers = await searchShopping(env.SERPAPI_KEY, query, region);
  await env.SNAG.put(key, JSON.stringify(offers), { expirationTtl: OFFER_CACHE_SECONDS });
  return offers;
}

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === "/v1/health") {
    return json({ ok: true, shopping: Boolean(env.SERPAPI_KEY), gifts: Boolean(env.ANTHROPIC_API_KEY), push: Boolean(env.APNS_KEY_P8) });
  }

  if (env.SNAG_SHARED_SECRET && request.headers.get("X-Snag-Key") !== env.SNAG_SHARED_SECRET) {
    return error("Unauthorized", 401);
  }

  // GET /v1/offers?q=...&country=us&currency=USD
  if (url.pathname === "/v1/offers" && request.method === "GET") {
    if (!env.SERPAPI_KEY) return error("Live shopping search is not configured", 501);
    const query = (url.searchParams.get("q") ?? "").slice(0, 200);
    if (!query) return error("Missing q", 400);
    const region = regionFromCountry(url.searchParams.get("country"));
    try {
      return json({ offers: await cachedOffers(env, query, region) });
    } catch (e) {
      return error(e instanceof Error ? e.message : "Search failed", 502);
    }
  }

  // POST /v1/gifts { recipient, giver, prompt, count }
  if (url.pathname === "/v1/gifts" && request.method === "POST") {
    if (!env.ANTHROPIC_API_KEY) return error("Cloud gift ideas are not configured", 501);
    const body = (await request.json().catch(() => null)) as GiftRequestBody | null;
    if (!body?.prompt) return error("Missing prompt", 400);
    try {
      return json({ ideas: await generateGiftIdeas(env.ANTHROPIC_API_KEY, body) });
    } catch (e) {
      if (e instanceof GiftRefusalError) return error(e.message, 422);
      if (e instanceof Anthropic.RateLimitError) return error("Busy, try again shortly", 429);
      if (e instanceof Anthropic.APIError) return error(`Model error ${e.status}`, 502);
      return error("Couldn't generate ideas", 500);
    }
  }

  // POST /v1/watch — register or update a watched product for this device.
  if (url.pathname === "/v1/watch" && request.method === "POST") {
    const device = deviceID(request);
    if (!device) return error("Missing X-Snag-Device", 400);
    const registration = (await request.json().catch(() => null)) as WatchRegistration | null;
    if (!registration?.productID || !registration.query || !REGIONS.includes(registration.region) || !registration.rule) {
      return error("Invalid watch", 400);
    }
    const key = watchKey(device, registration.productID);
    const existing = await env.SNAG.get<StoredWatch>(key, "json");
    const stored: StoredWatch = { ...(existing ?? { history: [] }), deviceID: device, registration };
    await env.SNAG.put(key, JSON.stringify(stored));
    return new Response(null, { status: 204 });
  }

  // DELETE /v1/watch/:productID
  const del = url.pathname.match(/^\/v1\/watch\/(.+)$/);
  if (del?.[1] && request.method === "DELETE") {
    const device = deviceID(request);
    if (!device) return error("Missing X-Snag-Device", 400);
    await env.SNAG.delete(watchKey(device, decodeURIComponent(del[1])));
    return new Response(null, { status: 204 });
  }

  return error("Not found", 404);
}

function watchKey(device: string, productID: string): string {
  return `watch:${device}:${productID}`;
}

function regionFromCountry(country: string | null): Region {
  switch ((country ?? "").toLowerCase()) {
    case "gb":
    case "uk":
      return "uk";
    case "de":
    case "fr":
    case "es":
    case "it":
    case "nl":
      return "eu";
    default:
      return "us";
  }
}

/** Cron: re-price watched products and push when an alert fires. */
export async function checkWatches(env: Env): Promise<{ checked: number; pushed: number }> {
  if (!env.SERPAPI_KEY) return { checked: 0, pushed: 0 };
  const listed = await env.SNAG.list({ prefix: "watch:", limit: 1000 });
  const watches: { key: string; watch: StoredWatch }[] = [];
  for (const { name } of listed.keys) {
    const watch = await env.SNAG.get<StoredWatch>(name, "json");
    if (watch) watches.push({ key: name, watch });
  }
  // Oldest-checked first, bounded per run to protect the search budget.
  watches.sort((a, b) => (a.watch.lastCheckedAt ?? "").localeCompare(b.watch.lastCheckedAt ?? ""));

  let checked = 0;
  let pushed = 0;
  for (const { key, watch } of watches.slice(0, WATCHES_PER_RUN)) {
    const { registration } = watch;
    const currency = REGION_CURRENCY[registration.region];
    let offers: Offer[];
    try {
      offers = await cachedOffers(env, registration.query, registration.region);
    } catch {
      continue;
    }
    checked++;
    watch.lastCheckedAt = isoDate();
    const best = bestOffer(offers, currency);
    if (!best) {
      await env.SNAG.put(key, JSON.stringify(watch));
      continue;
    }
    const total = best.price + (best.shipping ?? 0);
    const previous = watch.history.map((h) => h.price);
    watch.history = [...watch.history, { date: isoDate(), price: total, merchant: best.merchant }].slice(-60);
    if (best.url) watch.bestURL = best.url;
    watch.bestMerchant = best.merchant;

    const fire = evaluateAlert(registration.rule, total, previous);
    if (fire && registration.apnsToken && env.APNS_KEY_P8) {
      const text = alertText(best.title ?? registration.query, fire, currency, best.merchant);
      const alive = await sendPush(env, registration.apnsToken, {
        ...text,
        productID: registration.productID,
        url: best.url,
        timeSensitive: fire.reason === "allTimeLow",
      });
      if (!alive) {
        await env.SNAG.delete(key);
        continue;
      }
      registration.rule = { ...registration.rule, lastNotifiedPrice: fire.price, lastNotifiedAt: isoDate() };
      pushed++;
    }
    await env.SNAG.put(key, JSON.stringify(watch));
  }
  return { checked, pushed };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env);
  },
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(checkWatches(env).then(() => undefined));
  },
} satisfies ExportedHandler<Env>;

import type { Offer, Region } from "./types";
import { isoDate, REGION_COUNTRY, REGION_CURRENCY } from "./types";

/** Subset of a SerpApi Google Shopping result we use. */
export interface SerpShoppingResult {
  title?: string;
  source?: string;
  link?: string;
  product_link?: string;
  price?: string;
  extracted_price?: number;
  delivery?: string;
  second_hand_condition?: string;
  thumbnail?: string;
}

export function normalizedDomain(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  try {
    const host = new URL(raw.includes("://") ? raw : `https://${raw}`).hostname.toLowerCase();
    return host.replace(/^(www\.|m\.)/, "");
  } catch {
    return undefined;
  }
}

/** "Free delivery" → 0, "$5.99 delivery" → 5.99, otherwise unknown. */
export function parseDelivery(delivery: string | undefined): number | undefined {
  if (!delivery) return undefined;
  if (/free/i.test(delivery)) return 0;
  const match = delivery.match(/(\d+(?:[.,]\d{2})?)/);
  return match?.[1] ? Number(match[1].replace(",", ".")) : undefined;
}

export function mapSerpResults(results: SerpShoppingResult[], region: Region, now = new Date()): Offer[] {
  const currency = REGION_CURRENCY[region];
  const offers: Offer[] = [];
  results.forEach((r, index) => {
    if (typeof r.extracted_price !== "number" || r.extracted_price <= 0) return;
    const url = r.link ?? r.product_link;
    const domain = normalizedDomain(r.link);
    const condition = !r.second_hand_condition
      ? "new"
      : /refurb|renewed/i.test(r.second_hand_condition)
        ? "refurbished"
        : "used";
    const offer: Offer = {
      id: `serp-${index}-${(r.source ?? "shop").toLowerCase().replace(/[^a-z0-9]+/g, "-")}`,
      merchant: r.source ?? domain ?? "Shop",
      price: r.extracted_price,
      currency,
      condition,
      channel: "online",
      updatedAt: isoDate(now),
      source: "google-shopping",
    };
    if (domain && !domain.endsWith("google.com")) offer.merchantDomain = domain;
    if (r.title) offer.title = r.title;
    if (url) offer.url = url;
    const shipping = parseDelivery(r.delivery);
    if (shipping !== undefined) offer.shipping = shipping;
    offers.push(offer);
  });
  return offers;
}

export async function searchShopping(
  apiKey: string,
  query: string,
  region: Region,
  fetcher: typeof fetch = fetch,
): Promise<Offer[]> {
  const url = new URL("https://serpapi.com/search.json");
  url.searchParams.set("engine", "google_shopping");
  url.searchParams.set("q", query);
  url.searchParams.set("gl", REGION_COUNTRY[region]);
  url.searchParams.set("hl", "en");
  url.searchParams.set("num", "30");
  url.searchParams.set("api_key", apiKey);
  const response = await fetcher(url.toString());
  if (!response.ok) throw new Error(`Shopping search failed: ${response.status}`);
  const body = (await response.json()) as { shopping_results?: SerpShoppingResult[]; inline_shopping_results?: SerpShoppingResult[] };
  return mapSerpResults([...(body.shopping_results ?? []), ...(body.inline_shopping_results ?? [])], region);
}

/** Cheapest new, in-currency online offer, ignoring obvious mismatches. */
export function bestOffer(offers: Offer[], currency: string): Offer | undefined {
  const candidates = offers.filter(
    (o) => o.channel === "online" && o.currency === currency && (o.condition === "new" || o.condition === "unknown") && o.price > 0,
  );
  if (candidates.length === 0) return undefined;
  const totals = candidates.map((o) => o.price + (o.shipping ?? 0)).sort((a, b) => a - b);
  const median = totals[Math.floor(totals.length / 2)] ?? 0;
  const sane = candidates.length >= 3 ? candidates.filter((o) => o.price + (o.shipping ?? 0) >= median * 0.35) : candidates;
  return sane.reduce<Offer | undefined>((best, o) => {
    const total = o.price + (o.shipping ?? 0);
    return !best || total < best.price + (best.shipping ?? 0) ? o : best;
  }, undefined);
}

import { describe, expect, it } from "vitest";
import { alertText, evaluateAlert } from "../src/alerts";
import { base64url } from "../src/apns";
import { toGiftIdeas } from "../src/gifts";
import { bestOffer, mapSerpResults, normalizedDomain, parseDelivery } from "../src/offers";
import { isoDate, type PriceAlertRule } from "../src/types";

describe("offers", () => {
  it("maps SerpApi shopping results to Snag offers", () => {
    const offers = mapSerpResults(
      [
        { title: "Sony WH-1000XM6", source: "Best Buy", link: "https://www.bestbuy.com/site/123", extracted_price: 329.99, delivery: "Free delivery" },
        { title: "Sony WH-1000XM6", source: "eBay", link: "https://www.ebay.com/itm/1", extracted_price: 210, second_hand_condition: "used", delivery: "$7.50 delivery" },
        { title: "No price", source: "Shop" },
      ],
      "us",
      new Date("2026-10-26T12:00:00.456Z"),
    );
    expect(offers).toHaveLength(2);
    expect(offers[0]).toMatchObject({ merchant: "Best Buy", merchantDomain: "bestbuy.com", price: 329.99, shipping: 0, currency: "USD", condition: "new", channel: "online" });
    expect(offers[0]?.updatedAt).toBe("2026-10-26T12:00:00Z");
    expect(offers[1]).toMatchObject({ condition: "used", shipping: 7.5 });
  });

  it("parses delivery text and domains", () => {
    expect(parseDelivery("Free delivery")).toBe(0);
    expect(parseDelivery("£4,99 delivery")).toBe(4.99);
    expect(parseDelivery(undefined)).toBeUndefined();
    expect(normalizedDomain("https://www.Argos.co.uk/product/1")).toBe("argos.co.uk");
  });

  it("picks the cheapest sane new offer", () => {
    const base = { channel: "online" as const, currency: "USD", condition: "new" as const, source: "t" };
    const best = bestOffer(
      [
        { ...base, id: "a", merchant: "A", price: 300 },
        { ...base, id: "b", merchant: "B", price: 280, shipping: 10 },
        { ...base, id: "c", merchant: "C", price: 285 },
        { ...base, id: "case", merchant: "Case", price: 15 },
      ],
      "USD",
    );
    expect(best?.id).toBe("c");
  });
});

describe("alerts", () => {
  const rule = (trigger: PriceAlertRule["trigger"], extra: Partial<PriceAlertRule> = {}): PriceAlertRule => ({
    trigger, baselinePrice: 100, currency: "USD", isEnabled: true, ...extra,
  });

  it("matches the app's rules", () => {
    expect(evaluateAlert(rule({ targetPrice: { _0: 80 } }), 81, [])).toBeNull();
    expect(evaluateAlert(rule({ targetPrice: { _0: 80 } }), 79, [])?.reason).toBe("reachedTarget");
    expect(evaluateAlert(rule({ percentDrop: { _0: 0.15 } }), 86, [])).toBeNull();
    expect(evaluateAlert(rule({ percentDrop: { _0: 0.15 } }), 84, [])?.reason).toBe("droppedByPercent");
    expect(evaluateAlert(rule({ anyDrop: {} }), 97, [])?.reason).toBe("dropped");
    expect(evaluateAlert(rule({ allTimeLow: {} }), 90, [95, 91])?.reason).toBe("allTimeLow");
    expect(evaluateAlert(rule({ allTimeLow: {} }), 91, [95, 90])).toBeNull();
  });

  it("does not repeat at the same price", () => {
    expect(evaluateAlert(rule({ anyDrop: {} }, { lastNotifiedPrice: 90 }), 90, [])).toBeNull();
    expect(evaluateAlert(rule({ anyDrop: {} }, { lastNotifiedPrice: 90 }), 85, [])).not.toBeNull();
    expect(evaluateAlert(rule({ anyDrop: {} }, { isEnabled: false }), 10, [])).toBeNull();
  });

  it("writes notification text", () => {
    const text = alertText("Headphones", { price: 279, dropFraction: 0.2, reason: "droppedByPercent" }, "GBP", "Argos");
    expect(text.title).toBe("Price drop: Headphones");
    expect(text.body).toBe("Now £279 at Argos (−20%). Tap to grab it.");
  });
});

describe("shared helpers", () => {
  it("formats dates the way Swift decodes them", () => {
    expect(isoDate(new Date("2026-01-02T03:04:05.678Z"))).toBe("2026-01-02T03:04:05Z");
  });

  it("base64url-encodes without padding", () => {
    expect(base64url('{"alg":"ES256"}')).toBe("eyJhbGciOiJFUzI1NiJ9");
  });

  it("clamps and fills gift ideas", () => {
    const ideas = toGiftIdeas(
      [{ title: "Pottery class", pitch: "p", whyThem: "t", whyYou: "y", kind: "experience", estimatedPrice: 0, searchQuery: "", personalTouch: "", delight: 3 }],
      "GBP",
      6,
    );
    expect(ideas[0]).toMatchObject({ kind: "experience", searchQuery: "Pottery class", delight: 1, currency: "GBP", origin: "cloudAI" });
    expect(ideas[0]?.estimatedPrice).toBeUndefined();
    expect(ideas[0]?.id).toMatch(/^[0-9A-F-]{36}$/);
  });
});

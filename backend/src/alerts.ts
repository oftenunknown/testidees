import type { PriceAlertRule } from "./types";

// Mirrors SnagKit's AlertEvaluator so server and device agree on when to alert.

export const MINIMUM_MEANINGFUL_DROP = 0.02;
export const RENOTIFY_STEP = 0.01;

export type AlertReason = "reachedTarget" | "droppedByPercent" | "dropped" | "allTimeLow";

export interface AlertFire {
  price: number;
  dropFraction: number;
  reason: AlertReason;
}

export function evaluateAlert(rule: PriceAlertRule, currentBest: number, historyPrices: number[]): AlertFire | null {
  if (!rule.isEnabled || currentBest <= 0 || rule.baselinePrice <= 0) return null;
  if (rule.lastNotifiedPrice !== undefined && currentBest > rule.lastNotifiedPrice * (1 - RENOTIFY_STEP)) return null;

  const drop = (rule.baselinePrice - currentBest) / rule.baselinePrice;
  const t = rule.trigger;

  if ("targetPrice" in t) {
    return currentBest <= t.targetPrice._0 ? { price: currentBest, dropFraction: drop, reason: "reachedTarget" } : null;
  }
  if ("percentDrop" in t) {
    return drop >= t.percentDrop._0 ? { price: currentBest, dropFraction: drop, reason: "droppedByPercent" } : null;
  }
  if ("anyDrop" in t) {
    return drop >= MINIMUM_MEANINGFUL_DROP ? { price: currentBest, dropFraction: drop, reason: "dropped" } : null;
  }
  const previousLow = historyPrices.length > 0 ? Math.min(...historyPrices) : rule.baselinePrice;
  return currentBest < previousLow * (1 - RENOTIFY_STEP / 2) ? { price: currentBest, dropFraction: drop, reason: "allTimeLow" } : null;
}

export function formatMoney(amount: number, currency: string): string {
  const cents = Math.round(amount * 100) % 100 !== 0;
  return new Intl.NumberFormat("en", { style: "currency", currency, maximumFractionDigits: cents ? 2 : 0, minimumFractionDigits: cents ? 2 : 0 }).format(amount);
}

export function alertText(title: string, fire: AlertFire, currency: string, merchant?: string): { title: string; body: string } {
  const heading =
    fire.reason === "allTimeLow" ? `Lowest price ever: ${title}` : fire.reason === "reachedTarget" ? `Target hit: ${title}` : `Price drop: ${title}`;
  let body = `Now ${formatMoney(fire.price, currency)}`;
  if (merchant) body += ` at ${merchant}`;
  if (fire.dropFraction > 0.005) body += ` (−${Math.round(fire.dropFraction * 100)}%)`;
  return { title: heading, body: `${body}. Tap to grab it.` };
}

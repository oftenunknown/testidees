// JSON shapes shared with the iOS app. They mirror SnagKit's Codable types,
// so keep field names in sync with Packages/SnagKit.

export type Region = "us" | "uk" | "eu" | "other";

export interface Offer {
  id: string;
  merchant: string;
  merchantDomain?: string;
  title?: string;
  price: number;
  shipping?: number;
  currency: string;
  url?: string;
  condition: "new" | "used" | "refurbished" | "unknown";
  channel: "online" | "inStore";
  inStock?: boolean;
  /** ISO 8601 without fractional seconds (Swift's .iso8601 decoder rejects them). */
  updatedAt?: string;
  location?: string;
  source: string;
}

/** Swift encodes enums with unlabeled associated values as {"case": {"_0": value}}. */
export type AlertTrigger =
  | { targetPrice: { _0: number } }
  | { percentDrop: { _0: number } }
  | { anyDrop: Record<string, never> }
  | { allTimeLow: Record<string, never> };

export interface PriceAlertRule {
  trigger: AlertTrigger;
  baselinePrice: number;
  currency: string;
  isEnabled: boolean;
  lastNotifiedPrice?: number;
  lastNotifiedAt?: string;
}

export interface WatchRegistration {
  productID: string;
  gtin?: string;
  query: string;
  region: Region;
  rule: PriceAlertRule;
  apnsToken?: string;
}

export interface StoredWatch {
  deviceID: string;
  registration: WatchRegistration;
  history: { date: string; price: number; merchant?: string }[];
  lastCheckedAt?: string;
  bestURL?: string;
  bestMerchant?: string;
}

export type GiftKind = "object" | "experience" | "consumable" | "subscription" | "personalised";

export interface GiftIdea {
  id: string;
  title: string;
  pitch: string;
  whyThem: string;
  whyYou: string;
  kind: GiftKind;
  interests: string[];
  estimatedPrice?: number;
  currency: string;
  searchQuery: string;
  personalTouch?: string;
  cardMessage?: string;
  delight: number;
  fit: number;
  origin: "cloudAI";
}

export interface Env {
  SNAG: KVNamespace;
  SERPAPI_KEY?: string;
  ANTHROPIC_API_KEY?: string;
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_BUNDLE_ID?: string;
  APNS_PRODUCTION?: string;
  SNAG_SHARED_SECRET?: string;
}

/** Date → ISO 8601 that Swift's JSONDecoder(.iso8601) accepts. */
export function isoDate(date: Date = new Date()): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export const REGION_COUNTRY: Record<Region, string> = { us: "us", uk: "gb", eu: "de", other: "us" };
export const REGION_CURRENCY: Record<Region, string> = { us: "USD", uk: "GBP", eu: "EUR", other: "USD" };

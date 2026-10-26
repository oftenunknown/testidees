import Anthropic from "@anthropic-ai/sdk";
import type { GiftIdea, GiftKind } from "./types";

// Cloud gift ideas for devices without Apple Intelligence. The app builds the
// brief (GiftPromptBuilder) so on-device, Private Cloud Compute and this
// endpoint all see the same description of the two people.

const SYSTEM = `You are a gifting expert with exceptional taste who knows what is currently available to buy.
Recommend specific, buyable gifts that feel personal and surprising but are still right for the recipient.
Each idea must fit both what the recipient loves and the giver's personality, so the gift feels unmistakably from them.
Avoid generic gifts (gift cards, mugs, socks, candles) unless there is a specific, personal twist.
Give realistic price estimates in the recipient's currency and a shop search query that would find the item.
Keep every text field short: titles under 8 words, reasons under 20 words.`;

const KINDS: GiftKind[] = ["object", "experience", "consumable", "subscription", "personalised"];

const IDEA_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["ideas"],
  properties: {
    ideas: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "pitch", "whyThem", "whyYou", "kind", "estimatedPrice", "searchQuery", "personalTouch", "delight"],
        properties: {
          title: { type: "string" },
          pitch: { type: "string" },
          whyThem: { type: "string" },
          whyYou: { type: "string" },
          kind: { type: "string", enum: KINDS },
          estimatedPrice: { type: "number" },
          searchQuery: { type: "string" },
          personalTouch: { type: "string" },
          delight: { type: "number" },
        },
      },
    },
  },
} as const;

interface DraftIdea {
  title: string;
  pitch: string;
  whyThem: string;
  whyYou: string;
  kind: GiftKind;
  estimatedPrice: number;
  searchQuery: string;
  personalTouch: string;
  delight: number;
}

export interface GiftRequestBody {
  prompt: string;
  count?: number;
  recipient?: { currency?: string };
}

export class GiftRefusalError extends Error {}

export async function generateGiftIdeas(apiKey: string, request: GiftRequestBody, client = new Anthropic({ apiKey })): Promise<GiftIdea[]> {
  const prompt = request.prompt.slice(0, 8000);
  const currency = request.recipient?.currency ?? "USD";

  const response = await client.beta.messages.create({
    model: "claude-opus-5-5",
    max_tokens: 16000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: SYSTEM,
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: IDEA_SCHEMA },
    },
    messages: [{ role: "user", content: prompt }],
  });

  if (response.stop_reason === "refusal") {
    throw new GiftRefusalError("The model declined to suggest gifts for this request.");
  }

  const text = response.content
    .filter((block): block is Anthropic.Beta.BetaTextBlock => block.type === "text")
    .map((block) => block.text)
    .join("");
  const parsed = JSON.parse(text) as { ideas: DraftIdea[] };
  return toGiftIdeas(parsed.ideas, currency, request.count ?? 6);
}

export function toGiftIdeas(drafts: DraftIdea[], currency: string, limit: number): GiftIdea[] {
  return drafts.slice(0, limit).map((d) => {
    const idea: GiftIdea = {
      id: crypto.randomUUID().toUpperCase(),
      title: d.title,
      pitch: d.pitch,
      whyThem: d.whyThem,
      whyYou: d.whyYou,
      kind: KINDS.includes(d.kind) ? d.kind : "object",
      interests: [],
      currency,
      searchQuery: d.searchQuery || d.title,
      delight: Math.min(1, Math.max(0, d.delight)),
      fit: 0.8,
      origin: "cloudAI",
    };
    if (d.estimatedPrice > 0) idea.estimatedPrice = d.estimatedPrice;
    if (d.personalTouch) idea.personalTouch = d.personalTouch;
    return idea;
  });
}

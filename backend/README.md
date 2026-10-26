# Snag server (optional)

The iOS app works without a server: it reads barcodes, prices and shelf
prices from free sources (UPCitemdb, Open Food Facts, Open Prices), uses Apple
Intelligence for gift ideas, and checks watched prices in the background on
the phone.

This Cloudflare Worker adds three things:

| Endpoint | What it adds | Needs |
|---|---|---|
| `GET /v1/offers?q=&country=` | Live Google Shopping prices from hundreds of shops | `SERPAPI_KEY` |
| `POST /v1/watch`, `DELETE /v1/watch/:id` + cron every 30 min | Price checks around the clock, with push notifications even when the phone is asleep | `SERPAPI_KEY`, APNs key |
| `POST /v1/gifts` | AI gift ideas for phones without Apple Intelligence (Claude Opus 5.5) | `ANTHROPIC_API_KEY` |

`GET /v1/health` reports which of these are switched on.

## Deploy

```bash
cd backend
npm install
npx wrangler login
npx wrangler kv namespace create SNAG       # paste the id into wrangler.toml
npx wrangler secret put SERPAPI_KEY          # https://serpapi.com
npx wrangler secret put ANTHROPIC_API_KEY    # optional
npx wrangler secret put APNS_KEY_P8          # paste the AuthKey_XXXX.p8 contents
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler deploy
```

Then in the app: **Settings → Price sources → Snag server**, paste the
`https://snag-backend.<you>.workers.dev` URL.

Create the APNs key at developer.apple.com → Keys → + → Apple Push
Notifications service. Set `APNS_BUNDLE_ID` in `wrangler.toml` if you changed the bundle ID.

## Develop

```bash
npm run typecheck
npm test
npm run dev
```

## Privacy

The server stores, per device: the watched product's search query, alert rule
and APNs token. Gift requests carry the recipient profile you typed in (name,
interests, budget) and are sent to the Anthropic API when `/v1/gifts` is used;
nothing is stored.

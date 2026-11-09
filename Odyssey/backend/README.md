# Odyssey token server (optional)

Strava's OAuth has no PKCE, so exchanging a sign-in code for tokens needs your
API app's **client secret**. Odyssey supports two setups:

| Setup | Good for | Secret lives |
|---|---|---|
| Paste Client ID + Secret in **Settings → Strava API app** | Testing with your own account | Your iPhone's Keychain |
| This Worker, URL in **Settings → Token server** (or baked in at build time) | TestFlight builds for friends | Cloudflare secret |

The Worker only exchanges, refreshes and revokes tokens. Activity data goes
straight from Strava to the phone and never passes through it.

| Endpoint | Body | Does |
|---|---|---|
| `POST /v1/strava/token` | `{"code": "…"}` | Authorisation code → tokens (Strava's response, unchanged) |
| `POST /v1/strava/refresh` | `{"refresh_token": "…"}` | Fresh access token |
| `POST /v1/strava/revoke` | `{"token": "…"}` | Disconnects the athlete |
| `GET /v1/health` | | Whether it's configured |

## Deploy

The easy way: add the Cloudflare and Strava secrets described in
[Share it with friends](../README.md#share-it-with-friends), and the
`Odyssey TestFlight` workflow tests and deploys this Worker on every run, then
bakes its URL into the build.

By hand:

```bash
cd Odyssey/backend
npm install
npx wrangler login
npx wrangler secret put STRAVA_CLIENT_ID
npx wrangler secret put STRAVA_CLIENT_SECRET
npx wrangler secret put ALLOWED_ATHLETE_IDS   # optional: "12345,67890"
npx wrangler deploy
```

Then either enter `https://odyssey-token-server.<you>.workers.dev` in the app,
or set the repository variable `ODYSSEY_TOKEN_SERVER` so the
`Odyssey TestFlight` workflow bakes it into builds.

`ALLOWED_ATHLETE_IDS` keeps strangers from spending your Strava quota: anyone
not on the list is refused and their new grant is revoked immediately.

## Develop

```bash
npm test
npm run typecheck
```

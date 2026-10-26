# Getting Snag onto TestFlight

The `TestFlight` GitHub Actions workflow builds a signed release on GitHub's
Xcode 27.1 runner and uploads it to App Store Connect. You don't need a Mac.
You do need a paid Apple Developer Program membership.

## One-time setup (about 10 minutes)

### 1. Create an App Store Connect API key

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Under **Team Keys**, click **+**, name it `GitHub Actions` and give it the **Admin** role.
   Admin is needed so Xcode can create the distribution certificate and provisioning profile for you (cloud signing).
3. Download the `AuthKey_XXXXXXXXXX.p8` file. You can only download it once.
4. Note the **Key ID** (next to the key) and the **Issuer ID** (at the top of the page).

### 2. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → **Team ID** (10 characters).

### 3. Register the bundle ID and create the app record

1. [Certificates, Identifiers & Profiles → Identifiers → +](https://developer.apple.com/account/resources/identifiers/add/bundleId):
   App ID, explicit bundle ID `com.oftenunknown.snag` (or your own — see step 4).
   Tick **Push Notifications**. In-App Purchase is on by default.
2. [App Store Connect → Apps → + → New App](https://appstoreconnect.apple.com/apps): platform iOS,
   any name that's free on the App Store (e.g. "Snag – Deals & Gifts"), pick the bundle ID above, SKU `snag`.

### 4. Add the secrets to GitHub

Repository → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | Key ID from step 1 |
| `ASC_ISSUER_ID` | Issuer ID from step 1 |
| `ASC_KEY_P8` | The full contents of the `.p8` file, including the `BEGIN/END PRIVATE KEY` lines |
| `APPLE_TEAM_ID` | Team ID from step 2 |

If you used a different bundle ID, add a repository **variable** (Variables tab) named `BUNDLE_ID`.

## Uploading a build

Actions tab → **TestFlight** → **Run workflow**, or push a tag:

```bash
git tag testflight-1 && git push origin testflight-1
```

The run takes about 10 minutes. Apple then processes the build (usually 5–20 minutes)
before it shows in App Store Connect → your app → **TestFlight**.

## Testing on your devices

1. In TestFlight → **Internal Testing**, create a group and add yourself (and anyone on your team).
2. Install the **TestFlight** app on each iPhone, accept the invite, and install Snag.
3. Every new workflow run uploads a new build number automatically.

## Testing Premium without buying

TestFlight uses Apple's sandbox, so in-app purchases are free there once the
subscriptions exist in App Store Connect (Monetisation → Subscriptions: group
"Snag Premium", products `snag.premium.monthly` and `snag.premium.yearly`).

To skip that setup for now, open **Settings → Premium → Tester unlock** inside the
app. The toggle only appears in TestFlight and Xcode builds.

## Troubleshooting

- **"No profiles for 'com.oftenunknown.snag' were found"**: the API key needs the Admin role, and the bundle ID must be registered (step 3).
- **"Cannot determine the Apple ID from Bundle ID"** on upload: create the app record in App Store Connect (step 3.2).
- **"The bundle version must be higher than the previously uploaded version"**: re-run the workflow; build numbers come from the run number.

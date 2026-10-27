# Getting Snag onto TestFlight

The `TestFlight` GitHub Actions workflow builds a signed release on GitHub's
Xcode 27.1 runner and uploads it to App Store Connect. You don't need a Mac,
but a computer makes steps 1 and 5 easier (you download a key file and paste
its contents).

**Before you start:** you need a paid [Apple Developer Program](https://developer.apple.com/programs/enroll/)
membership and the Account Holder or Admin role on it. New enrolments can take
up to 48 hours to be approved. Your test devices need iOS 27.0 or later.

## 1. Create an App Store Connect API key

This lets the workflow sign and upload on your behalf.

1. Open [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. First time only: click **Request Access** and accept the terms (Account Holder only).
3. On the **Team Keys** tab, click **+** (or **Generate API Key**). Name it `GitHub Actions` and choose the **Admin** role.
   Admin lets Xcode create the signing certificate and provisioning profile for you.
4. Click **Download API Key** to get `AuthKey_XXXXXXXXXX.p8`. You can only download it once.
5. Note the **Key ID** (in the key's row) and the **Issuer ID** (the long ID above the table).

## 2. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → **Team ID** (10 characters).

## 3. Register the bundle ID

1. Open [Certificates, Identifiers & Profiles → Identifiers → +](https://developer.apple.com/account/resources/identifiers/add/bundleId).
2. Choose **App IDs** → Continue → **App** → Continue.
3. Description `Snag`, Bundle ID **Explicit** `com.oftenunknown.snag`.
   If that ID is taken, use your own (e.g. `com.yourname.snag`) and add it as the `BUNDLE_ID` variable in step 5.
4. Under Capabilities, tick **Push Notifications**. Leave the rest as they are.
5. Continue → **Register**.

## 4. Create the app record

1. [App Store Connect → Apps](https://appstoreconnect.apple.com/apps) → **+** → **New App**.
2. Platform **iOS**. Name: anything not already on the App Store, e.g. "Snag – Deals & Gifts"
   (the home-screen name stays "Snag"). Pick a primary language, choose the bundle ID from step 3,
   SKU `snag`, User Access **Full Access** → **Create**.

## 5. Add the secrets to GitHub

[Repository → Settings → Secrets and variables → Actions](https://github.com/oftenunknown/testidees/settings/secrets/actions) → **New repository secret**, once for each:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | Key ID from step 1 |
| `ASC_ISSUER_ID` | Issuer ID from step 1 |
| `ASC_KEY_P8` | The full contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_TEAM_ID` | Team ID from step 2 |

To copy the `.p8` contents, open it in TextEdit or Notepad. From a Mac terminal with the GitHub CLI you can instead run
`gh secret set ASC_KEY_P8 --repo oftenunknown/testidees < ~/Downloads/AuthKey_XXXXXXXXXX.p8`.

If you used a different bundle ID, add a repository **variable** (Variables tab) named `BUNDLE_ID`.

## 6. Build and upload

[Actions → TestFlight](https://github.com/oftenunknown/testidees/actions/workflows/testflight.yml) → **Run workflow**, or push a tag:

```bash
git tag testflight-1 && git push origin testflight-1
```

The run takes about 10–15 minutes. Apple then processes the build (usually 5–30 minutes)
and emails you when it's ready.

## 7. Add yourself as a tester

1. App Store Connect → your app → **TestFlight** tab.
2. Next to **Internal Testing** in the sidebar, click **+**. Name the group (e.g. "Me"),
   tick **Enable automatic distribution** → **Create**.
3. In the group, click **+** next to Testers and add yourself. Others must first be invited
   as users under Users and Access.

No export-compliance question should appear: the app already declares it uses no non-exempt encryption.

## 8. Install on your devices

1. Install the **TestFlight** app from the App Store on each iPhone or iPad.
2. Open the invite email on the device → **View in TestFlight** → **Accept** → **Install**
   (or just open TestFlight while signed in with the same Apple ID).
3. Every later workflow run uploads a new build number, and TestFlight offers it as an update.
   Builds expire after 90 days.

## Testing Premium without buying

TestFlight uses Apple's sandbox, so in-app purchases are free there once the
subscriptions exist in App Store Connect (Monetisation → Subscriptions: group
"Snag Premium", products `snag.premium.monthly` and `snag.premium.yearly`).

To skip that setup for now, open **Settings → Premium → Tester unlock** inside the
app. The toggle only appears in TestFlight and Xcode builds.

## Troubleshooting

- **"Missing repository secrets"**: one of the four secrets in step 5 is missing or misspelled.
- **"No profiles for 'com.oftenunknown.snag' were found"** or **"not authorized"**: the API key needs the Admin role, and the bundle ID must be registered (step 3).
- **"Cannot determine the Apple ID from Bundle ID"** on upload: create the app record (step 4) with the same bundle ID the workflow uses.
- **Errors mentioning an agreement**: sign in at [developer.apple.com/account](https://developer.apple.com/account) and accept any pending agreement shown in the banner.
- **"The bundle version must be higher than the previously uploaded version"**: re-run the workflow; build numbers come from the run number.

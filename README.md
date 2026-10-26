# Snag — deals, price alerts & gifts that feel like you

An iOS 27 app (SwiftUI, Liquid Glass) for finding the best price on anything,
checking in a shop whether a price is good, watching prices, and getting gift
ideas that blend the recipient's interests with *your* personality.
Built for iPhone 18 Pro / Pro Max and iPhone Duo (outer and inner displays).

## What's in it

| Area | Highlights |
|---|---|
| **Scan** (prominent tab) | Point the camera: barcode and shelf-tag price are read together, the product is looked up and a *good price?* gauge appears — no buttons. Photo recognition for items without a barcode. |
| **Best price** | Offers from UPCitemdb, crowd-sourced shelf prices from Open Prices, and optionally live Google Shopping via the Snag server. Ranked by *effective* price after your perks and saved codes. |
| **Perks** | Student, NHS, Blue Light, military, teacher, senior, new-customer… mapped to UNiDAYS, Student Beans, TOTUM, ID.me, Blue Light Card, Health Service Discounts, Defence Discount Service and more. Scheme logins live in the Keychain. |
| **Checkout agent** | In-app browser that finds the promo box, tries your codes, keeps the best, fills scheme logins on the scheme's own site, and saves codes you copy. |
| **Wishlist & alerts** | One-tap *Watch* with a smart 10%-drop alert; target price, % drop, any drop or all-time low; price-history chart; background checks and notifications with a *Buy now* action. |
| **Gift Studio** (Premium) | A gifting persona built from a 10-tap quiz, photos/Instagram screenshots (on-device Vision), an Instagram data export, and shopping history; AI portrait and Image Playground avatar. Recipient profiles get ideas from Apple Intelligence (Private Cloud Compute for Premium), each with why-it-fits-them, why-it's-from-you, and a live best price. |
| **Premium** | StoreKit 2 subscriptions (`snag.premium.monthly`, `snag.premium.yearly`). TestFlight builds have a tester unlock. |

### iPhone Duo

- **Outer display:** compact layout; Scan and the screen's actions live in toolbars, so
  iOS 27.1 places them in the vertical side bar next to the camera. Scan prefers
  toolbar items when the bar is crowded; lists prefer the tab bar.
- **Inner display:** regular width — list and detail side by side (Wishlist, Gifts),
  and Scan shows camera and result in a fold-aware `ArrangementView` so nothing
  sits on the crease.
- **Folding/unfolding:** navigation state lives in the app model, so you stay on
  the same item; detail screens switch layout with `AnyLayout`, so content glides
  rather than reloads. Half-folded (tabletop) Scan splits camera and result
  across the fold (`onHingeChange`).

## Layout

```
App/                 iOS app (SwiftUI)
Packages/SnagKit/    Platform-independent logic: pricing verdicts, alerts, GTIN,
                     discounts, persona & gift engine, API clients (+55 tests)
UITests/             Screenshot tour run in CI on iPhone 18 Pro, Pro Max and Duo
backend/             Optional Cloudflare Worker (live prices, push alerts, cloud AI)
project.yml          XcodeGen spec
docs/TESTFLIGHT.md   How to ship to TestFlight from GitHub Actions
```

## Building

```bash
brew install xcodegen
xcodegen generate
open Snag.xcodeproj        # Xcode 27.1+, iOS 27 SDK
```

Core logic tests run anywhere Swift 6.2+ runs:

```bash
swift test --package-path Packages/SnagKit
```

CI (`.github/workflows/ios.yml`) builds the app on GitHub's `xcode-27` runner and
uploads screenshots from the iPhone 18 Pro, 18 Pro Max and iPhone Duo simulators.
`.github/workflows/testflight.yml` signs and uploads to TestFlight — see
[docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).

## Data sources and honesty

- Prices come from third parties and can be stale; every offer shows when it was seen.
- Discount percentages for schemes are typical values, marked *est.*; the real
  saving is confirmed at checkout by the agent.
- Instagram's public API no longer exposes personal profiles, so Snag learns from
  what you choose to share: screenshots, or the JSON from Instagram's
  *Download your information*. Photos are analysed on device and only labels are kept.

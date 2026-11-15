# Lead Gen iPhone app

Capacitor 8 shell (Swift Package Manager, no CocoaPods) around the owner dashboard at
https://leadgen-admin-alpha.vercel.app/m.

- App name: **Lead Gen**. Bundle id: `com.antonzarwel.leadgenadmin`. iPhone only, iOS 15+.
- Loads the live site (`server.url` in `capacitor.config.json`), so web changes ship without a new build.
  `www/` is only the offline fallback page.
- Face ID lock (native, `ios/App/App/SceneDelegate.swift`, LocalAuthentication): locks every time the app goes to
  the background and covers the screen in the app switcher. Falls back to the device passcode.
- Login: the normal admin login page inside the app. The `lg_auth` cookie lasts 30 days.

## Build and ship (GitHub Actions)

`.github/workflows/testflight.yml` runs on `macos-26` (Xcode 26 is required for uploads), archives with
automatic signing through the App Store Connect API key, and uploads to TestFlight (internal testing).
Run it from the Actions tab (Run workflow) or push a `v*` tag.

Repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (full .p8 text), `APPLE_TEAM_ID`.
The API key needs the Admin role (cloud managed distribution certificate).

Before the first run, the App Store Connect app record must exist with bundle id
`com.antonzarwel.leadgenadmin`, and the bundle id must be registered (automatic signing registers it
if the key is Admin).

## Cost

macOS minutes count 10x on private repos (2,000 free min/month = about 200 macOS min, roughly
10 to 15 builds). A public repo builds free; this repo holds no secrets.

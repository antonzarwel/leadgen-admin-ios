# Lead Gen iPhone app

Native SwiftUI app for running the lead gen business. No web view.

- App name: **Lead Gen**. Bundle id `com.antonzarwel.leadgenadmin`. iPhone, iOS 17+.
- Project: `ios/LeadGen/project.yml` (XcodeGen). CI generates `LeadGen.xcodeproj`; it is not committed.
- Data: read only JSON from leadgen-admin (`https://leadgen-admin-alpha.vercel.app`):
  `POST /api/m/login` (password to token), `GET /api/m/summary`, `/api/m/leads?days=90`, `/api/m/clients`, `/api/m/sites`.
  The token goes in `Authorization: Bearer`, it is kept in the Keychain, and rotating `ADMIN_SECRET` revokes it.
- Last good responses are cached on device (Caches, file protection on), so the app opens instantly.
- Face ID (or passcode) locks the app every time it goes to the background; the app switcher shows a cover.

## Screens

Today (KPIs, leads chart, latest leads), Leads (search, filters, day sections, swipe to call, detail),
Clients (MRR, leads, unpaid, detail with chart, leads, sites, invoices, payments), Money (MRR, paid,
unpaid and overdue, Wise or email dues, invoice draft queue), Sites (rented, free, own, leads, Search Console).

## Build and ship

`.github/workflows/testflight.yml` runs `bash ci/build.sh` on `macos-26` (Xcode 26) for every push to main
that touches `ci/**` or `ios/**`. The script installs XcodeGen, archives unsigned, then exports with
automatic App Store signing through the App Store Connect API key and uploads to TestFlight.
Build number = 100 + run number.

Repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.
`package.json` and `package-lock.json` are stubs that only exist because the workflow's setup-node step wants a lockfile.

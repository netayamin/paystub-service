# Drop Feed — iOS (SwiftUI)

Native iOS app for the Drop Feed backend. Shows Top Opportunities, Hot Right Now, and All Drops.

## Run on Simulator

1. Open `DropFeed.xcodeproj` in Xcode (from the `ios/` folder).
2. Start the backend: `make dev-backend` (from project root).
3. Select an iPhone simulator and press **Run** (⌘R).

The app reads the API base URL from **Info.plist** → `API_BASE_URL` (default `http://127.0.0.1:8000` for simulator).

## Run on Your Phone (ngrok — works off WiFi)

1. Install ngrok: `brew install ngrok` (sign up at ngrok.com for a free auth token). Start backend: `make dev-backend` (Terminal 1).
2. From project root, run **`make ngrok-ios`** (Terminal 2). This starts ngrok and sets `API_BASE_URL` in Info.plist to the ngrok HTTPS URL.
3. Rebuild the app in Xcode (⌘B then ⌘R). Connect your iPhone via USB, select it as the run destination, and run.

Alternatively: run `make ngrok` (foreground), copy the https URL, then edit `ios/DropFeed/Info.plist` and set `API_BASE_URL` to that URL; rebuild.

When ngrok restarts, run `make ngrok-ios` again (or update `API_BASE_URL` in Info.plist) and rebuild. **Same WiFi:** Set `API_BASE_URL` to `http://YOUR_MAC_IP:8000` in Info.plist.

## Build & run from Cursor (Sweetpad)

1. Install the [Sweetpad](https://marketplace.visualstudio.com/items?itemName=sweetpad.sweetpad) extension (and optionally the [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) extension and [xcode-build-server](https://github.com/SolaWing/xcode-build-server) via Homebrew for autocomplete).
2. Open the **project root** (the repo root that contains `ios/`) in Cursor — not the `.xcodeproj` or `ios/` folder alone.
3. Run **Sweetpad: Generate Build Server Config** from the Command Palette (⇧⌘P). This creates a `buildServer.json` in the project root so the Xcode Build Server works with the project.
4. From the Command Palette or the Sweetpad sidebar (🍭), select the **DropFeed** target/scheme, choose a simulator or device, then build and run.

## First Run

You may need to trust the developer certificate:

- **Settings → General → VPN & Device Management → [Your Apple ID] → Trust**

## Push notifications (APNs) — new drops in background

Push is enabled in the project (`DropFeed.entitlements`). **Requires a real device** (simulator does not get APNs tokens).

**Switch to APNs (checklist):**

1. **Apple Developer:** [Keys](https://developer.apple.com/account/resources/authkeys/list) → **+** → name the key → enable **Apple Push Notifications service (APNs)** → Continue → Register → **Download** the .p8 file (once only). Note the **Key ID** (10 chars). Get **Team ID** from Membership or top-right of the portal.
2. **Backend** (e.g. on EC2 in `backend/.env`):
   ```env
   APNS_KEY_ID=YourKeyId10chars
   APNS_TEAM_ID=YourTeamId10chars
   APNS_BUNDLE_ID=com.dropfeed.app
   APNS_KEY_P8_PATH=/path/to/AuthKey_XXXXX.p8
   APNS_USE_SANDBOX=true
   ```
   Or use `APNS_KEY_P8_BASE64=<base64 of .p8>` instead of `APNS_KEY_P8_PATH`. For App Store builds use `APNS_USE_SANDBOX=false`.
3. **Migration:** On the server run `cd backend && poetry run alembic upgrade head` (creates `push_tokens` table if not done).
4. **Restart backend** (e.g. `sudo docker-compose -f docker-compose.prod.yml up -d` on EC2).
5. **iPhone:** Build and run the app, allow notifications. The device token is sent to the backend. New drops will push within ~1 minute even when the app is in the background or closed.

## Structure

- `DropFeedApp.swift` — App entry
- `AppDelegate.swift` — Push registration (forwards device token to backend)
- `ContentView.swift` — Root view
- `Models/Drop.swift` — API response models
- `Services/APIService.swift` — HTTP client (base URL from Info.plist `API_BASE_URL`)
- `Views/` — FeedView, DropCardView
- `ViewModels/FeedViewModel.swift` — Fetch + 15s polling

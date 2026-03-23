# Drop Feed — iOS (SwiftUI)

Native iOS app for the Drop Feed backend. Shows Top Opportunities, Hot Right Now, and All Drops.

## Run on Simulator

1. Open `DropFeed.xcodeproj` in Xcode (from the `ios/` folder).
2. Start the backend: `make dev-backend` (from project root).
3. Select an iPhone simulator and press **Run** (⌘R).

The app reads the API base URL from **Info.plist** → `API_BASE_URL` (default `http://127.0.0.1:8000` for simulator).

## Run on Your Phone (ngrok — works off WiFi)

From repo root, run **`make ios-phone`** for the checklist.

**Recommended flow (no hand-editing Info.plist):**

1. **Terminal A:** `make dev-backend` (listens on `0.0.0.0:8000`).
2. **Terminal B:** `ngrok http 8000` (leave it running; free ngrok account is fine).
3. **Xcode:** select your iPhone and **Run** (⌘R). A build phase reads ngrok’s local API (`127.0.0.1:4040`) and writes the **HTTPS tunnel URL** into the **built** app’s `Info.plist`. The file in git stays `http://127.0.0.1:8000` (simulator still uses your Mac).

If ngrok is **not** running when you build for a device, the app falls back to the deploy server (see `APIService` — localhost in the bundle is ignored on device).

**Phone sign-in testing:** set `AUTH_OTP_FIXED=123456` in `backend/.env`, restart the backend, then enter `123456` in the app.

**Optional:** `make ngrok-ios` still patches `ios/DropFeed/Info.plist` in the repo; the build-time inject above is usually enough.

**Same Wi‑Fi only:** set `API_BASE_URL` in `Info.plist` to `http://YOUR_MAC_IP:8000` and rebuild.

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

## Optional: Use ACarousel library

The Live tab uses a built-in snap carousel (peek, 5s auto-play, pause on drag). To use the [ACarousel](https://github.com/JWAutumn/ACarousel) Swift Package instead:

1. In Xcode: **File → Add Package Dependencies…**
2. Enter: `https://github.com/JWAutumn/ACarousel`
3. Add the **ACarousel** product to the DropFeed target.
4. In `FeedView.swift`: add `import ACarousel` and replace the `JustDroppedCarouselSection` body with the ACarousel-based implementation (see the comment in that struct).

## Structure

- `DropFeedApp.swift` — App entry
- `AppDelegate.swift` — Push registration (forwards device token to backend)
- `ContentView.swift` — Root view
- `Models/Drop.swift` — API response models
- `Services/APIService.swift` — HTTP client (base URL from Info.plist `API_BASE_URL`)
- `Views/` — FeedView, DropCardView
- `ViewModels/FeedViewModel.swift` — Fetch + 15s polling

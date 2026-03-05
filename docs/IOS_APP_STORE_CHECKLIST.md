# iOS App Store Release Checklist

Before submitting to the App Store:

## 1. API configuration

- **Production URL**: Set `API_BASE_URL` in `ios/DropFeed/Info.plist` to your production backend (e.g. `https://api.yourdomain.com`). For HTTP (non-HTTPS), the host must be listed under `NSExceptionDomains` in `NSAppTransportSecurity`.
- Do **not** use `NSAllowsArbitraryLoads`; keep specific exception domains only.

## 2. App icons and launch screen

- **App icons**: Add all required sizes to `ios/DropFeed/Assets.xcassets/AppIcon.appiconset`. Xcode can generate these from a single 1024×1024 image.
- **Launch screen**: Add a `LaunchScreen.storyboard` or configure the default launch screen in the target’s General → App Icons and Launch Screen so the app doesn’t show a black or blank flash.

## 3. Testing

- Run on **multiple device sizes** (e.g. iPhone SE, iPhone 15 Pro Max) in the simulator.
- Test with **airplane mode** or no network to confirm the “You’re offline” / error state and Retry behavior.
- Test **filters** (date, party size, time) and confirm empty states when no results match.

## 4. Final checks

- **Version and build**: Set `CFBundleShortVersionString` and build number in the target.
- **Privacy**: If you use tracking or analytics, add a Privacy Policy URL and configure App Tracking Transparency if required.
- **Signing**: Use an Apple Developer account and the correct provisioning profile for distribution.

# OctetSample — iOS dev sample

Minimal demo app exercising only the public v1 SDK surface
(`Octet.start(...)` + `sdk.loc.isWithin(...)`). One button, one
verdict. Pairs with `samples-public/android-sample/` on the Android
side.

This is the **dev-time copy**. It consumes the SDK source via a local
SwiftPM path dependency (`path: ../../ios`) so SDK changes propagate
to the sample immediately — no release roundtrip required. Use it to
smoke-test new SDK features as you write them.

A **consumer-facing copy** lives at `octet-sdk-ios/sample/` in the
distribution repo. It consumes the published xcframework via SwiftPM
URL; the release workflow mirrors source changes from here on every
tagged release (see `.github/workflows/release-ios.yml`).

## Setup (license key)

The SDK won't start without a v1 license key. Get one at
[api.octetproof.com/signup](https://api.octetproof.com/signup), or
issue one from your own self-hosted activation backend. Then:

```bash
# In samples-public/ios-sample/ :
cp LocalConfig.swift.example LocalConfig.swift
# Open LocalConfig.swift and paste your key into LocalConfig.licenseKey.
```

`LocalConfig.swift` is gitignored. If you skip this step the build
fails with `cannot find 'LocalConfig' in scope` pointing at
`ContentView.swift` — loud and clear.

## Build

`project.yml` is the canonical source; the `.xcodeproj` is gitignored
and generated on demand. Install XcodeGen once (`brew install
xcodegen`), then from `samples-public/ios-sample/`:

```bash
xcodegen generate
open OctetSample.xcodeproj
# or from the CLI:
xcodebuild -project OctetSample.xcodeproj \
           -scheme OctetSample \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build
```

Bundle ID: `com.octetproof.sample`.

When running on a real device, set the **Apple Team ID** in the
target's *Signing & Capabilities* panel. Required `Info.plist`
entries are already in place (`NSLocationWhenInUseUsageDescription`
for the location pipeline, `NSMotionUsageDescription` because the SDK
touches `CMMotionActivityManager` at init).

## What it does

1. Requests `LocationWhenInUseUsageDescription`.
2. Calls `try await Octet.start(config: OctetConfig(licenseKey:
   LocalConfig.licenseKey))`. The SDK verifies the license key, hits
   `/v1/activate` if needed, caches the activation token in Keychain,
   then brings up the proof pipeline.
3. On tap, runs `await sdk.loc.isWithin(region: .country(isoCode:
   "US"), atTime: Date())` and renders the verdict (`result` /
   `reason` / `message` / whether a proof attached).

Source: `ContentView.swift`. Imports `OctetSDK` (the SwiftPM
target inside the wrapper); the consumer-facing copy in
`octet-sdk-ios/sample/` rewrites this to `OctetSDK` (the published
wrapper framework) during the release-mirror step.

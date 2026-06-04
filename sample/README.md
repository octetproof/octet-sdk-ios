# OctetV1Toy — iOS sample app

Minimal demo of the OctetSDK public API: country dropdown, live device
map, one verdict button. Use this to confirm your environment is set up
correctly and to play with the predicate API without the noise of a
full app.

## What it does

- Requests **Location When In Use** on launch.
- Calls `try await Octet.start(config: OctetConfig(licenseKey:))` —
  the SDK verifies your license, activates against
  `api.octetproof.com/v1/activate` on first run, caches the activation
  token in Keychain, and brings up the proof pipeline.
- Centers the MapKit map on the device's current GPS fix (no API key
  required on Apple platforms).
- On button tap, runs
  `await sdk.loc.isWithin(region: .country(isoCode: …), atTime: Date())`
  against the country you picked from the dropdown and renders the
  verdict (result / reason / message / whether a proof attached).

## Prerequisites

- iOS 17.0+ on the device (the demo uses the iOS-17 SwiftUI Map API).
  The SDK itself supports iOS 16+; your own host app can target 16.
- Xcode 15+ on macOS.
- A valid OctetSDK license key — free trial from
  [sdk.octetproof.com/signup](https://sdk.octetproof.com/signup).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install
  xcodegen`). The project ships as a `project.yml` spec rather than a
  committed `.xcodeproj` so it can be regenerated cleanly.

## 1. Configure your license key

```bash
cp LocalConfig.swift.example LocalConfig.swift
# Edit LocalConfig.swift and paste your key into LocalConfig.licenseKey.
```

`LocalConfig.swift` is gitignored — your key stays local. If you skip
this step the build fails with `cannot find 'LocalConfig' in scope`
pointing at the missing file.

## 2. Generate the Xcode project

```bash
xcodegen generate
```

This produces `OctetV1Toy.xcodeproj` in the same directory.

## 3a. Build & run via Xcode (IDE workflow)

```bash
open OctetV1Toy.xcodeproj
```

In Xcode:
1. Select the **OctetV1Toy** target → **Signing & Capabilities** →
   tick *Automatically manage signing* and pick your team.
2. Plug in your iOS device (or pick a simulator destination).
3. ⌘R to build and run.

The free Apple Developer tier works — apps installed via free
provisioning expire after 7 days. A paid Apple Developer Program
account removes the expiry.

## 3b. Build & run via command line (CI / scripting workflow)

Build for the simulator (no code signing needed):

```bash
xcodebuild \
  -project OctetV1Toy.xcodeproj \
  -scheme OctetV1Toy \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Build for a real device (requires a signing identity; pass
`-allowProvisioningUpdates` if Xcode hasn't yet provisioned the
device):

```bash
xcodebuild \
  -project OctetV1Toy.xcodeproj \
  -scheme OctetV1Toy \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

Install to a connected device using
[`ios-deploy`](https://github.com/ios-control/ios-deploy) (`brew
install ios-deploy`):

```bash
ios-deploy --bundle build/Release-iphoneos/OctetV1Toy.app
```

## First-launch permissions

You'll see two prompts on real-device runs:
- **Location When In Use** — grant it; the SDK refuses to start without
  location auth.
- **Motion & Fitness** — grant it; the SDK touches
  `CMMotionActivityManager` at init and Apple requires the usage
  description even for read-only access.

Then tap the button to fire a verdict.

## What the SDK ships as

A binary `OctetSDK.xcframework` — pinned to a specific version via
SwiftPM in `project.yml` (which points at the parent dist repo's
`Package.swift`). The xcframework statically links its internal
dependencies; you don't need to declare any extra Swift packages.

For the full SDK API surface, see the parent repository's
[README](../README.md) and [INTEGRATION.md](../INTEGRATION.md).

## License

The OctetSDK and this sample app are released under the terms in
[LICENSE](../LICENSE).

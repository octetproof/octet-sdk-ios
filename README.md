# OctetSDK for iOS

Binary distribution of the Octet SDK for iOS — Swift Package Manager and
Carthage manifests plus tagged `xcframework` releases.

> ⚠️ **`0.0.1-alpha` is deprecated.** The v1 license-key schema cutover
> shipped in **`0.0.2-alpha`** (2026-06-04). Tokens issued by the current
> production backend will fail to verify on `0.0.1-alpha` with
> `LicenseError.verificationFailed(.unsupportedSchema)` at `Octet.start`.
> Upgrade to `0.0.4-alpha` or later. See [CHANGELOG.md](CHANGELOG.md)'s
> `[0.0.2-alpha]` entry for details.

## Installation

### Swift Package Manager

In Xcode: **File → Add Packages…** and enter:

```
https://github.com/octetproof/octet-sdk-ios
```

Pin to a specific version (recommended) rather than tracking `main`.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/octetproof/octet-sdk-ios", exact: "0.0.4-alpha")
]
```

SwiftPM's `from:` selector won't match pre-release tags (`-alpha`,
`-beta`, etc.) — use `.exact` for the alpha. Once a non-prerelease
ships, `from: "0.0.2"` becomes valid.

### Carthage

In your `Cartfile`:

```
binary "https://raw.githubusercontent.com/octetproof/octet-sdk-ios/main/OctetSDK.json" ~> 0.0
```

Then in your Swift code:

```swift
import OctetSDK
```

Both SwiftPM and Carthage consumers import the same `OctetSDK` module.

## Getting a license key

OctetSDK requires a valid license key to start. Sign up at
[sdk.octetproof.com/signup](https://sdk.octetproof.com/signup) to obtain
one — a free trial key works for evaluation.

## Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+

## Host-app integration prerequisites

Before calling `Octet.start(...)`, add the following keys to your app's
`Info.plist`. The SDK won't run without them. See
[INTEGRATION.md](INTEGRATION.md) for the full list, the conditional
keys for background-location use, and sample copy.

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses your location to verify and prove your location
to services that request it.</string>

<key>NSMotionUsageDescription</key>
<string>This app uses motion data to detect when you're stationary or
moving, which improves the confidence of location proofs.</string>
```

## Releases

Each tagged release on this repository carries the `OctetSDK.xcframework.zip`
as an asset. See [Releases](https://github.com/octetproof/octet-sdk-ios/releases).

## Sample app

A standalone demo lives in [`sample/`](sample/) — clone, drop in your
license key, build. See [`sample/README.md`](sample/README.md) for both
command-line and Xcode workflows.

## License

See [LICENSE](LICENSE).

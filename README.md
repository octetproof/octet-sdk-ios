# OctetSDK for iOS

> **Cryptographically verifiable location proofs.** Every proof the SDK
> generates is a signed envelope a relying party can verify independently
> with the standalone [`octet-verify`](https://github.com/octetproof/octet-verify)
> CLI — no need to trust the SDK at runtime. Hardware-backed device keys
> where available (Secure Enclave on iOS, StrongBox on Android), with the
> actual key-storage tier reported in every proof so verifiers can decide
> what to accept.

## Quick start

```swift
// 1. In Package.swift
.package(url: "https://github.com/octetproof/octet-sdk-ios", exact: "1.1.0")

// 2. In your app code (inside an async context)
import OctetSDK

let sdk = try await Octet.start(config: OctetConfig(
    licenseKey: "octet_live_v4.public..."  // from sdk.octetproof.com/signup
))

let verdict = await sdk.loc.isWithin(region: .country(isoCode: "US"))
// verdict.result, verdict.reason, verdict.proof (LocationProof)
```

## How it works

The SDK runs a sensor-fusion + anti-spoofing pipeline on-device and emits
a `LocationProof` envelope as the cryptographic output of the
`sdk.loc.isWithin(...)` predicate. The envelope is signed by a
hardware-backed device key (Secure Enclave / StrongBox / software-backed,
honestly reported per-proof via `DeviceKeySecurityLevel`).

A relying party verifies the proof with the standalone
[`octet-verify`](https://github.com/octetproof/octet-verify) CLI or by
calling the Octet-hosted backend's verify endpoint. This lets a consumer
separate proof generation from proof acceptance — the SDK signs, an
independent verifier accepts.

## Installation

### Swift Package Manager

In Xcode: **File → Add Packages…** with the repository URL, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/octetproof/octet-sdk-ios", exact: "1.1.0")
]
```

### Carthage

```
binary "https://raw.githubusercontent.com/octetproof/octet-sdk-ios/main/OctetSDK.json" ~> 1.0
```

Both consumers `import OctetSDK`.

## Getting a license key

OctetSDK requires a valid license key to start. Sign up at
[sdk.octetproof.com/signup](https://sdk.octetproof.com/signup) — a free
trial key works for evaluation.

## Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+

## Host-app integration prerequisites

Before calling `Octet.start(...)`, add the location + motion usage keys
to your app's `Info.plist`. See [INTEGRATION.md](INTEGRATION.md) for the
full integration guide — `Info.plist` keys, device attestation (App Attest),
optional usage telemetry, opt-in TLS certificate pinning, log routing,
verdict reason codes, and reading the per-proof `DeviceKeySecurityLevel`.

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses your location to verify and prove your location
to services that request it.</string>

<key>NSMotionUsageDescription</key>
<string>This app uses motion data to detect when you're stationary or
moving, which improves the confidence of location proofs.</string>
```

## Releases

Each tagged release on this repository carries
`OctetSDK.xcframework.zip` as an asset. See
[Releases](https://github.com/octetproof/octet-sdk-ios/releases).

## Sample app

A standalone demo lives in [`sample/`](sample/) — clone, drop in your
license key, build. See [`sample/README.md`](sample/README.md) for both
command-line and Xcode workflows.

## License

See [LICENSE](LICENSE).

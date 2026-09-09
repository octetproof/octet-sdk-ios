# OctetSample — iOS sample

A SwiftUI demo of the public v1 SDK surface, built around two tabs:

- **Generate** — pick a region, watch the proof pipeline run (*SDK
  initialized → sensors warmed up → location fixed → proof generated*,
  with per-step timings and a map of your position), and get the
  predicate answer (`sdk.loc.isWithin(...)`). The result card shows the
  outcome, a confidence bucket, and the battery consumed by the run.
  Generated proofs are kept in a sample-owned store.
- **Verify** — run `Octet.verify(...)` on any stored or imported proof
  and read the grouped on-device checks (signature, freshness,
  hardware-attestation, …), with a one-line plain-language note on every
  check that couldn't run and how to make it run. Pick a region to check
  the proof's claim against, and see the granularity the proof reveals
  (nothing finer than its level). Proofs can be exported / imported as
  `.octetproof` files over AirDrop, Files, or the share sheet.

## Setup (activation)

**The SDK activates by attesting the app instance — there is no license key
to paste.** On a real device it uses **Apple App Attest** and bootstraps its
licence automatically on first launch. Copy the local config and set your
activation server:

```bash
# From this directory:
cp LocalConfig.swift.example LocalConfig.swift
# Open LocalConfig.swift and set your activation server URL.
```

`LocalConfig.swift` is gitignored. If you skip this step the build fails
with `cannot find 'LocalConfig' in scope` (from `AppModel.swift`) — loud
and clear.

**Run it on a real device — this sample is prod-only.** On a device with the
**App Attest** capability provisioned for its bundle id, the SDK attests and
bootstraps on first launch — nothing to paste (see **Build** below). The
simulator, CI, and a locally built debug app can't produce production
attestation; the SDK's sandbox-bootstrap path for those environments is covered
in the repository's `INTEGRATION.md` but is intentionally not wired into this
sample. Sign up at [octetproof.com](https://octetproof.com).

## Build

`project.yml` is the canonical source; the `.xcodeproj` is gitignored
and generated on demand. Install XcodeGen once (`brew install
xcodegen`), then from this directory:

```bash
xcodegen generate
open OctetSample.xcodeproj
# or from the CLI (simulator):
xcodebuild -project OctetSample.xcodeproj \
           -scheme OctetSample \
           -destination 'generic/platform=iOS Simulator' \
           -configuration Debug \
           CODE_SIGNING_ALLOWED=NO build
```

Bundle ID: `com.octetproof.sample`. Deployment target: iOS 17.

When running on a real device, set your **Apple Development Team** in
the target's *Signing & Capabilities* panel and provision an App ID
carrying the **App Attest** capability for the bundle id (the SDK
exercises Apple App Attest when the entitlement is present, and
degrades gracefully when it isn't). Required `Info.plist` entries are
already in place — `NSLocationWhenInUseUsageDescription` (the location
pipeline) and `NSMotionUsageDescription` (motion feeds proof
confidence).

> The proof pipeline needs real sensors: motion, GNSS, and cellular
> inputs are only present on a **physical device** — the simulator has no
> real motion / GNSS / cellular hardware.

## Files

| Area | Files |
|---|---|
| App shell / model | `OctetSampleApp.swift`, `RootView.swift`, `AppModel.swift`, `AppSettings.swift` |
| Generate | `GenerateView.swift` (pipeline, map, curated debug feed) |
| Verify + proofs | `VerifyView.swift`, `VerifyDetailView.swift`, `ViewRawView.swift`, `ImportPreviewView.swift`, `ProofStore.swift`, `ProofFile.swift`, `Models.swift` |
| Shared | `Theme.swift`, `Regions.swift`, `LocalConfig.swift.example` |

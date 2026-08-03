# OctetSDK for iOS — Integration Prerequisites

What every consumer app needs to provide for the SDK to start cleanly.
The SDK can't ship most of these on the host's behalf — they live in
the host app bundle by platform mandate.

---

## `Info.plist` keys

Add the following to your app's `Info.plist`. Without them the SDK
crashes on first launch with a privacy-sensitive-data error from the
iOS runtime — the message points at the missing key.

### Required

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses your location to verify and prove your location
to services that request it.</string>

<key>NSMotionUsageDescription</key>
<string>This app uses motion data to detect when you're stationary or
moving, which improves the confidence of location proofs.</string>
```

**Why `NSMotionUsageDescription` is non-negotiable:** the SDK
instantiates `CMMotionActivityManager` immediately during
`Octet.start(...)`. Apple requires the usage-description key before
any code touches that API, even read-only. Missing the key produces:

> This app has crashed because it attempted to access privacy-sensitive
> data without a usage description. The app's Info.plist must contain
> an NSMotionUsageDescription key with a string value explaining to
> the user how the app uses this data.

The strings are user-facing — write them in your product's voice; the
copy above is a safe default.

### Required only if you enable background location

If you call `Octet.start(config:)` with an `OctetConfig` that turns on
background location (i.e. you need proofs while the app is
backgrounded), add these too:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app uses background location to continue generating
location proofs while you're not actively using it.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

Without these the SDK silently falls back to foreground-only operation
when the app is backgrounded; the SDK itself does not crash, but proofs
stop generating until the app returns to foreground. Background
location updates are only enabled when both `backgroundLocationEnabled`
is configured *and* the user grants `.authorizedAlways`.

### Future sensors

If the SDK adds new privacy-gated APIs (camera, bluetooth, microphone,
HealthKit), each one drags in its own usage-description key. Re-check
this list when upgrading SDK major versions.

---

## Proof-upload data handling

When you enable proof-upload by setting `OctetConfig.proofUploadUrl`,
the SDK transmits each generated `LocationProof` envelope (proof bytes
+ license id + opaque device fingerprint hash) to the configured
backend. Default off; no proof leaves the device unless the URL is set.

If you point at Octet-hosted `api.octetproof.com`, **uploaded proofs
are retained at most ~24h solely to enable verification, then
permanently deleted; no long-term storage, no backups.** This window
exists so a verifier can audit a freshly-generated proof — it is an
ephemeral verification buffer, not an archive. If your application
needs a longer-lived record of a proof, fetch it from the backend
within the retention window and persist it yourself.

---

## Usage telemetry

The SDK collects **aggregate, privacy-preserving usage counters** — e.g. how many
proofs were generated, uploaded, or couldn't be produced, by coarse level and
region type — and reports them to the license backend, indexed by your license.
This is **on by default**; disable it with
`OctetConfig(licenseKey: …, telemetryEnabled: false)`.

The counters contain **no location data** — no coordinates, region IDs, or proof
contents; only aggregate integers and coarse enum labels. They're buffered in an
encrypted file in the app's private storage and uploaded at most once a day (plus
a best-effort flush when the app backgrounds); the SDK schedules no background
tasks for this. Disabling deletes any buffered file.

---

## Opt-in TLS certificate pinning

The SDK ships with a public-key pin set for `api.octetproof.com` (the
certificate-authority intermediate plus a backup pin). Pinning is **off
by default**; opt in by setting
`OctetConfig.advanced.enableCertPinning = true` before calling
`Octet.start(config:)`. When enabled, the SDK's URLSession delegate
evaluates the server's SPKI against the pin set and fails the
connection on mismatch.

Default-off keeps consumers who haven't opted in from seeing pinning
failures surface as opaque connection errors. The pin set is rotated
in lockstep with backend certificate rotations.

---

## Reading the device-key security tier

Every signed proof envelope carries the actual `DeviceKeySecurityLevel`
of the device key used to sign it. Three possible values:

| Level | Meaning |
|---|---|
| `HARDWARE_STRONGBOX` | Tamper-resistant secure element (not reachable on iOS — reserved for cross-platform parity) |
| `HARDWARE_TEE` | Secure Enclave (typical on iPhone / iPad with the SEP) |
| `SOFTWARE` | Software-stored key (fallback for devices without hardware-backed key storage) |

The level is exposed via the SDK's public attestation surface so a
relying party (your own verifier or the standalone `octet-verify` CLI)
can decide what to accept per the trust requirements of the
integration. The SDK does not refuse to operate when only `SOFTWARE`
storage is available — it generates honest proofs at the level
actually achieved, and the acceptance decision lives at the verifier.

---

## Device attestation

Every signed proof carries a hardware-backed **device attestation** via Apple
App Attest, so a relying party can confirm the proof came from a genuine app
instance on a genuine device. No integration code is required; it is part of
proof generation. How often a fresh attestation is produced is configurable via
`OctetConfig.advanced.attestationCadence` — `perSession`, `periodic(interval:)`
(default), or `perProof` (highest assurance, highest cost).

### Bootstrapping your verifier — `attestationEnrolmentBundle()`

If you run your own verifier, it needs this device key's hardware root to trust
the key's signatures. Normally that root arrives on the first proof a device
submits — but a freshly-deployed, scaled-out, or migrated verifier may not have
seen that proof yet. `Octet.attestationEnrolmentBundle()` closes that gap:

```swift
if let bundle = Octet.attestationEnrolmentBundle() {
    let json = bundle.jsonString()      // canonical v:1 envelope
    // POST json to your verifier's enrolment endpoint
}
```

It returns `nil` until the device key has been attested (i.e. after the first
proof of the install). The call is cheap and local (a Keychain read, no network),
and the bundle is attestation evidence — not a secret — so it is safe to send and
to call repeatedly.

### Handling an unsupported-version error

`Octet.start(...)` can throw `LicenseError.upgradeRequired(minVersion:message:)`
when the backend stops supporting the running SDK version. It carries an optional
`minVersion` and human-readable `message`. Handle it by prompting the user to
update the app; a live session already running is unaffected. `LicenseStatus` also
exposes non-fatal hints — `upgradeRecommended` and `minSupportedVersion` — that let
you nudge an upgrade before the hard cutoff. (Version gating is dormant until
enabled server-side, so you will not see these in 1.2.1 yet — wiring the handler
now keeps you ready.)

---

## Privacy manifest

The xcframework bundles a `PrivacyInfo.xcprivacy` declaring the SDK's collected data
types (precise/coarse location, device identifier, aggregate usage counters) and its
required-reason API usage (System Boot Time for the anchored license clock; UserDefaults
for a one-time device-id migration). Xcode aggregates it automatically into your app's
privacy report at build time — no action needed. Review it alongside your app's own
disclosures when you complete App Store privacy details.

---

## Session-binding (per-login proofs)

To turn a location proof into an authentication factor — "in this region, *for this
login, right now*" — pass the one-time nonce your login backend issued as
`sessionNonce`:

```swift
let verdict = await sdk.loc.isWithin(.country("US"), sessionNonce: loginNonce)
// forward verdict.proof to your login backend, which verifies the binding
```

The SDK commits `SHA256("octet-session-binding-v1" ‖ len ‖ nonce)` into the signed
proof and forces a fresh (uncached) proof — **the raw nonce never leaves the
device**. Your verifier (octet-verify ≥ 1.2.0), given the same expected nonce,
confirms the proof was made for that specific login; an older verifier simply
ignores the binding (NOT-CHECKED). `sessionNonce` must be **1…512 bytes** — empty or
larger returns an `invalidSessionNonce` verdict with no proof and no network call.
Omit it entirely for normal, cacheable proofs (behaviour is unchanged from 1.1.0).

---

## Interpreting a verdict — reason codes & achievable level

`isWithin` / `isOutside` / `contains` return an `OctetVerdict` whose `result` is a
trichotomy — `yes` / `no` / `indeterminate`. `indeterminate` means "can't answer
right now"; never silently treat it as `no`. The `reason` says why:

| Reason | Meaning | Typical handling |
|---|---|---|
| `insufficientPrecision` | Conditions can't support a proof at the requested precision. `achievableLevel` names the best level the SDK *could* reach. | Re-request at `achievableLevel`, or apply your own fallback — the SDK never silently down-levels. |
| `spoofingDetected` / `tampering` | A positive security signal — suspected spoofing, or device tampering. | Treat as untrusted; don't retry blindly. |
| `noFix` / `staleFix` / `noProofAtResolution` | No fresh fix yet / time outside the proof's validity window / cached proof too coarse for the query. | Retry shortly. |

When `result` is `indeterminate` with reason `insufficientPrecision`, read
`verdict.achievableLevel` to decide whether the coarser level is acceptable
before re-requesting.

---

## Custom log routing

The SDK emits structured log lines through a pluggable `LogSink`
interface. The platform default is `OSLogSink`, which forwards into
Apple's unified logging system.

Implement `LogSink` and pass it via `OctetConfig.logSink` to route the
SDK's log lines into your own observability pipeline. Release builds
default free-form interpolations to `.private` so coordinates and
license fragments do not appear in plain text in system logs.

---

## Sample copy attribution

The English-language strings in the `Info.plist` section above are
reference copy. You're free to use them verbatim, translate, or
rewrite for your brand. Apple's review reads these strings; reviewers
prefer specific, user-friendly explanations over generic "to function"
boilerplate.

---

## Verifying your OctetSDK download

Every release publishes a SHA-256 manifest and a build-provenance
attestation so you can confirm the framework you pulled is the genuine,
unmodified Octet artifact built by our release pipeline.

**Swift Package Manager verifies the framework automatically.** The
`checksum:` in `Package.swift` is checked against the downloaded
`OctetSDK.xcframework.zip` on resolution — a mismatch fails the build, so
no extra step is needed.

**Carthage, CocoaPods, or a manual download — verify by hand.** Download
`OctetSDK.xcframework.zip`, `SHASUMS256.txt`, and
`OctetSDK.xcframework.zip.sigstore.json` from the release into one
directory, then:

```sh
# 1. Confirm the bytes match the published SHA-256.
shasum -a 256 -c SHASUMS256.txt

# 2. Confirm the checksums were signed by the official release workflow
#    (keyless Sigstore signature over the manifest).
cosign verify-blob \
  --certificate SHASUMS256.txt.pem \
  --signature SHASUMS256.txt.sig \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/octetproof/octet-sdk/\.github/workflows/release-ios\.yml@' \
  SHASUMS256.txt

# 3. Confirm the archive was built by the official release workflow.
gh attestation verify OctetSDK.xcframework.zip \
  --bundle OctetSDK.xcframework.zip.sigstore.json \
  --repo octetproof/octet-sdk
```

Steps 1–2 (checksum + keyless cosign signature) are the required verification and
must both report success. Step 3 (`gh attestation verify`) applies only when a
`.sigstore.json` build-provenance bundle is attached to the release — 1.2.1 ships
**without** one (a private-source-repo limitation, tracked in `octetproof/octet-sdk#169`),
so skip step 3 if no bundle is present. Steps 2–3 use the attached files offline —
the GitHub CLI and cosign are needed, but no special repository access.

---

## Reference implementation

The sample app in [`sample/`](sample/) exercises the minimum viable
permission flow if you need a reference.

---

## Updates to this document

Updates to this document arrive with each SDK release. Re-check it
when upgrading.

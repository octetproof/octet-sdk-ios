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
license fragments do not appear in plain text in system logs; use the
SDK's debug-mode toggle if you need them visible during development.

---

## Sample copy attribution

The English-language strings in the `Info.plist` section above are
reference copy. You're free to use them verbatim, translate, or
rewrite for your brand. Apple's review reads these strings; reviewers
prefer specific, user-friendly explanations over generic "to function"
boilerplate.

---

## Reference implementation

The sample app in [`sample/`](sample/) exercises the minimum viable
permission flow if you need a reference.

---

## Updates to this document

Updates to this document arrive with each SDK release. Re-check it
when upgrading.

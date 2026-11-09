# OctetSDK for iOS — Integration Prerequisites

What every consumer app needs to provide for the SDK to start cleanly.
The SDK can't ship most of these on the host's behalf — they live in
the host app bundle by platform mandate.

---

## Activation

As of 2.0.0 the SDK activates by **attesting the app instance**: at
`Octet.start` it proves the running app with **Apple App Attest** and bootstraps
its licence from the Octet backend. There is no license key to paste; a device
that cannot attest and carries no sandbox token fails closed.

**What you need**

- A real device, with the **App Attest** capability provisioned for your app's
  bundle id.
- Your app registered with Octet, so the backend recognises it. Sign up at
  [octetproof.com](https://octetproof.com).

`OctetConfig.licenseKey` is deprecated. `Octet.start` ignores it, so leave it
out: `OctetConfig()` needs no arguments. Code that still passes it builds with a
deprecation warning. It will be removed in the next major version.

### Simulator, CI, and debug builds — sandbox bootstrap

A build that can't produce production App Attest — the simulator, a CI runner,
or a locally built debug app — activates instead with a **sandbox bootstrap
token** set on `OctetConfig.sandboxBypassToken`, which you self-serve from your
account at [octetproof.com](https://octetproof.com). A release (App Store)
build cannot use a sandbox token: the SDK refuses it before the request is
built, and the backend rejects a sandbox token for a release app row.

The side an app lands on follows its signature, not its build configuration: an
Xcode Release build installed with a development profile lands on sandbox.

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

The SDK collects **privacy-preserving usage telemetry** (counters and per-proof events) and reports it
to the license backend (`POST /v1/metrics`), indexed by the license the SDK was
activated with. It is **on by default** and disclosed under the Octet Terms &
Conditions; disable it entirely by setting `telemetryEnabled = false` on your
`OctetConfig`.

**What it never contains.** No coordinates, no positions, no region geometry, no
proof bytes, no message text — **no precise location data of any kind** — and **no
new device identifier** (it reuses the opaque fingerprint established at
activation). It is **encrypted at rest** (AES-256-GCM, with a key held in the
platform keystore) and sent over TLS.

**Base counters (whenever telemetry is on).** Aggregate counts of proofs
generated / uploaded / dropped, bucketed by coarse dimensions only — proof
**level**, region **type** (country / city / …), and failure **stage** — plus the
SDK version and platform. Buffered in a single rolling file and uploaded at most
once a day (with a best-effort flush when the app backgrounds); no background
scheduler.

**Additional diagnostic signals (remotely gated).** Octet turns these on through
remote configuration, without an app release, and they are on for all licenses.
To keep the base counters but not these, set `flagsEnabled = false`, which stops
the SDK from receiving remote configuration. They add:

- **Per-proof events** — one flat record per proof, every field a bucketed **enum
  label** (the proof level and internal quality labels). The one field beyond pure enums is a coarse
  **region identity** — an **ISO 3166 country / subdivision code** (e.g. `US`,
  `GB-ENG`), never finer than the level the proof already claims and bounded to
  ISO 3166 space, not free text. Still no coordinates.
- **Background proof facts.** Every background proof can also report the country
  or subdivision code the device was resolved to, whether or not your app asked
  about that region. The reports also cover how the location was found (for
  example GPS or the cell network), the proof's confidence and generation time as
  ranges, and the app's location-permission state. Still no coordinates.
- **Configuration exposure.** Which remote-configuration variant the device
  received, with a pseudonymous device key, sent to `/v1/exposure`.
- **Error diagnostics** — a count of `(error type, call site)` pairs for errors
  caught at the SDK's public API boundary, with any message mapped to a fixed enum
  (`license` / `region_decode` / … / `unknown`) — never the raw message, never
  PII; capped at 50 distinct pairs.

**Your control.** All of the above, base and gated, stops entirely when
`telemetryEnabled = false`. No counters are recorded, the persisted file is
deleted, and `/v1/metrics` and `/v1/exposure` are never called. Three requests
continue: the license heartbeat, the remote-configuration fetch (SDK version,
platform, OS version, app ID and a pseudonymous device key), and the daily usage
record described below.

---

## Usage reporting

Octet bills per active device. To count devices, the SDK sends **one usage record
per device per UTC day**: after the first proof the app generates that day, it
queues a single `device_active` record and sends it with the next background
heartbeat. Later proofs that day send nothing more.

**What it contains.** The operation name, a timestamp and a record ID. The ID is a
one-way SHA-256 hash of the device's opaque activation fingerprint and the date, so it
changes every day and lets the server ignore duplicates. The device is counted from the
activation credentials the SDK already holds. **No location, no coordinates, no proof
data, no user or account identity, and no new device identifier.**

**It never affects a proof.** The record is written after the proof exists and needs
no network at that moment. A failed send is retried on later heartbeats, and a record
that could not be sent within 30 days is dropped. A sandbox session sends nothing.

**It is always on.** Reporting can't be switched off. `OctetConfig.creditServiceUrl` defaults to
`https://credits.octetproof.com`; set it only to point a test build at another
environment. Setting it to `nil` does not disable reporting.

---

## Routing all SDK traffic through your own gateway

By default the SDK talks to the Octet backend at `api.octetproof.com` and, for a
couple of enrichment calls, to a third-party host (IP-geolocation on iOS; GNSS
broadcast-ephemeris servers on Android). If your app's network surface is audited
— a firewall allowlist, an app-store network disclosure, or a "the app only talks
to our own domain" policy — you can route **every** SDK request through a reverse
proxy you operate, so the only backend the app visibly contacts is yours.

Choose the mode at `start()`:

```swift
let config = OctetConfig(
    advanced: AdvancedConfig(
        transport: TransportPolicy(
            mode: .integratorGateway,
            gateway: "https://api.example.com/octet")))
```

The SDK then sends every request to `{gateway}{path}`; your proxy forwards each
path to its upstream and returns the response unchanged. Activation, verification,
and proof/flag signing still terminate at Octet — the proxy is a plain forwarder,
so trust is unchanged and only the network topology moves.

### Consolidate onto Octet's own gateway instead (`octetGateway`)

If you want a single consolidated backend domain but would rather **not run a proxy
yourself**, select `octetGateway`. The SDK routes every call — first-party *and* the
third-party enrichment — through Octet's own hosted gateway, so
the app's only backend domain becomes that one Octet host:

```swift
let config = OctetConfig(
    advanced: AdvancedConfig(transport: .octetGateway))   // or TransportPolicy.octetGateway
```

There is **no `gateway` to supply** — the host is built in, and any value you set is
ignored — and nothing for you to operate. `octetGateway` uses standard
certificate-authority validation (TLS pinning is **off**); the `pins` field is ignored
in this mode — it applies only to the app→proxy hop of `integratorGateway`. The
`fallbackToDirect` option and the two notes below (the `/ext/geo/…` route, the IP hint) apply
here just the same. Everything from here on describes `integratorGateway`, the
run-your-own-proxy mode.

### What your proxy must forward

| The SDK sends (under your gateway) | Forward it to | Notes |
|---|---|---|
| `/v1/bootstrap/challenge`, `/v1/bootstrap`, `/v1/heartbeat` | `https://api.octetproof.com/v1/…` | activation. Never modify the body. |
| `/v1/flags`, `/v1/metrics`, `/v1/credits/…` | `https://api.octetproof.com/v1/…` | flag bundles are signed — never modify |
| `/v1/proofs`, `/v1/proofs/auth`, `/v1/proofs/challenge` | `https://api.octetproof.com/v1/…` | proof body up to 256 KiB — never modify |
| `/v1/exposure` | `https://api.octetproof.com/v1/…` | **both SDKs**. Usage reporting. Sent only with `telemetryEnabled` on. Body not signed. |
| `/v1/network/observe` | `https://api.octetproof.com/v1/…` | **both SDKs**. A `GET` with no body. |
| `/v1/integrity/decode` | `https://api.octetproof.com/v1/…` | **both SDKs**. Sent only when your app calls `Octet.verifyOnline` with a Play Integrity decoder. Body not signed. |
| `/ext/ipgeo/…` | optional, see "IP-based country hint" below | **iOS SDK only** — IP location hint |
| `/ext/gnss/…` | `https://cddis.nasa.gov/archive/gnss/data/daily/…` (fallback `https://igs.ign.fr/pub/igs/data/…`) | **Android SDK only** — GNSS ephemeris (large files; may need NASA Earthdata credentials) |
| `/ext/geo/…` | `https://api.octetproof.com/ext/geo/…` | **both SDKs**. **First-party & bearer-authed** — forward it like a `/v1/…` route (preserve `Authorization`, send `Host: api.octetproof.com`), not like the third-party `ext` routes above. |

Forward the third-party `/ext/gnss/` route only if you embed the Android SDK; `/ext/geo/…` is first-party and applies to both.

**Contract:**

- **Preserve the request verbatim** — method, the path after the prefix, the query
  string, and all headers, especially `Authorization`, `Content-Type`, and any
  `X-Octet-…` header.
- **Never modify the body** of `/v1/proofs`, `/v1/flags`, `/v1/bootstrap/challenge`
  or `/v1/bootstrap`. Each signature is over the exact bytes, so any rewrite, even
  re-serialising the JSON, breaks verification. Forward every other body, including
  `/v1/heartbeat`, and the `Authorization` header unchanged as well.
- **Use TLS 1.2 or higher to the upstream**, verify the upstream certificate, and
  send `Host: api.octetproof.com` (and matching SNI) on the first-party routes.
- **Pass status codes and the `Retry-After` header through unchanged** — the SDK
  honours them on `429` and `503`.
- **Don't cap the request body below 256 KiB**, and give the upstream at least as
  generous a timeout as you give the SDK (activation and attestation can be slow).

### Reference configurations

Replace `api.example.com/octet` with your own gateway base URL, and keep only the
`ext` block for the platform(s) you ship.

**nginx**

```nginx
# All first-party routes are under /v1/ — activation, flags, metrics, credits,
# proofs (incl. /v1/proofs/auth + /v1/proofs/challenge), and network-observe.
location /octet/v1/ {
    proxy_pass                  https://api.octetproof.com/v1/;
    proxy_ssl_server_name       on;
    proxy_set_header Host       api.octetproof.com;
    proxy_pass_request_headers  on;
    client_max_body_size        256k;
}
# Android apps only:
location /octet/ext/gnss/  { proxy_pass https://cddis.nasa.gov/archive/gnss/data/daily/; proxy_ssl_server_name on; }
# All apps (first-party, bearer-authed):
location /octet/ext/geo/   { proxy_pass https://api.octetproof.com/ext/geo/; proxy_ssl_server_name on; proxy_set_header Host api.octetproof.com; }
```

**Cloudflare Worker**

```js
const UPSTREAM = {
  "/v1/":        "https://api.octetproof.com/v1/",                   // all first-party (incl. /v1/proofs/auth, /v1/proofs/challenge)
  "/ext/gnss/":  "https://cddis.nasa.gov/archive/gnss/data/daily/",  // Android apps
  "/ext/geo/":   "https://api.octetproof.com/ext/geo/",              // all apps (first-party)
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/octet/, "");   // strip your gateway prefix
    const match = Object.entries(UPSTREAM).find(([prefix]) => path.startsWith(prefix));
    if (!match) return new Response("not found", { status: 404 });
    const [prefix, base] = match;
    const target = base + path.slice(prefix.length) + url.search;
    // Forward method, headers, and body untouched; return the upstream response as-is.
    return fetch(target, {
      method: request.method,
      headers: request.headers,
      body: request.body,
      redirect: "follow",
    });
  },
};
```

**AWS** — two common patterns:

- **API Gateway (HTTP API):** add one HTTP-proxy integration per prefix — e.g.
  route `ANY /octet/v1/{proxy+}` to `https://api.octetproof.com/v1/{proxy}`, and
  one each for `/octet/ext/geo/` (all apps) and `/octet/ext/gnss/` (Android). Leave
  request-parameter mapping untouched so headers and the query string pass through
  unchanged.
- **CloudFront:** define one origin per upstream and one cache behaviour per path
  pattern (`/octet/v1/*`, `/octet/ext/geo/*`, `/octet/ext/gnss/*`). Attach an origin-request policy that forwards **all**
  headers, query strings, and cookies, and the managed `CachingDisabled` cache
  policy so nothing is buffered or rewritten. Set each origin to HTTPS-only.

### Two things to know

- **Certificate pinning:** the default pin set (next section) pins Octet's
  certificate, which no longer applies once traffic flows through your proxy — the
  app sees **your** certificate, not Octet's. To keep pin-level protection on the
  app→gateway hop, pass your proxy's own SPKI pins in the transport policy:

  ```swift
  transport: TransportPolicy(
      mode: .integratorGateway,
      gateway: "https://api.example.com/octet",
      pins: ["<base64-sha256-of-your-proxy-SPKI>", "<backup-pin>"])
  ```

  Compute a pin with `openssl x509 -in cert.pem -pubkey -noout | openssl pkey
  -pubin -outform DER | openssl dgst -sha256 -binary | openssl enc -base64`.
  **Pin a stable point in the chain — a CA intermediate or root — not an
  auto-rotating leaf:** a managed certificate (Cloudflare, ACME / Let's Encrypt)
  re-keys on renewal, which breaks a leaf-SPKI pin the next time it rotates. Always
  include a backup pin. Leave `pins` empty (the default) to rely on standard
  certificate-authority validation only.
- **Availability — optional fallback to direct (`fallbackToDirect`, default off):**
  if you'd rather the SDK keep working through a gateway *outage* than fail closed,
  set `fallbackToDirect: true`. After repeated transport-level failures to your
  gateway (connect / TLS / DNS / timeout — never HTTP status errors), the SDK
  temporarily reverts only these calls to Octet directly: activation and heartbeat,
  proof upload, credits, border-data updates, and the `/v1/integrity/decode` call.
  It then re-probes your gateway and switches back once it recovers. Flags, metrics,
  `/v1/exposure`, `/v1/network/observe`, `/ext/ipgeo/` and `/ext/gnss/` never fall
  back. **This suspends the single-domain guarantee while active.** During the outage
  the calls that fall back talk to `api.octetproof.com` directly, so a
  strict-compliance deployment should leave it **off** (the default).

  ```swift
  transport: TransportPolicy(
      mode: .integratorGateway,
      gateway: "https://api.example.com/octet",
      fallbackToDirect: true,      // opt in to outage resilience (default false)
      fallbackAfterFailures: 3)    // consecutive transport failures before it trips
  ```
- **Zero Apple attestation calls, at the cost of un-attested proofs (`osAttestationInGatewayModes`, default on):**
  in a gateway mode the SDK still runs per-proof **App Attest** (→Apple) by default — an
  OS call that can't be proxied. Set `osAttestationInGatewayModes: false` to skip it, so
  the app makes **zero** Apple attestation calls. The trade-off is deliberate and visible
  on the wire: those proofs are signed by the device key but are not
  hardware-*attested*, and a verifier reports them `attested: false` — its
  attestation-required gate **fails** them. Gate your own acceptance on the proof's
  `attested` flag, **not** on validity; any "must be hardware-attested" policy belongs in
  your verifier / license issuance, not in what the SDK emits. Bootstrap/activation still
  attests, so the app still activates.

  ```swift
  transport: TransportPolicy(
      mode: .octetGateway,
      osAttestationInGatewayModes: false)   // skip App Attest → un-attested proofs
  ```
- **Forward `/ext/geo/…` too:** in a gateway mode the SDK resolves country and state
  at `{gateway}/ext/geo/reverse`. If that call fails for any reason, including an HTTP
  error such as `404` from a proxy that does not forward the route, state proofs
  return `INDETERMINATE`. Country proofs may still resolve from the cell network.
  With `fallbackToDirect` on, a failed `/ext/geo/reverse` call uses the operating
  system's geocoder instead. This route is the only exception to the rule above: the
  other routes that fall back react to transport errors only, never to an HTTP status.
- **IP-based country hint:** with your own gateway (`integratorGateway`), Octet
  provides no upstream for `/ext/ipgeo/`. Leave that route unrouted, or set
  `TransportPolicy.thirdParty = .disable` so the SDK skips the lookup. The hint is
  optional, and a proof is still produced either way. `.octetGateway` serves the
  hint itself.

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

## Confidence score and assurance tier

By default, the SDK reports **no confidence score and no assurance tier**:

- `confidence` on a verdict or proof holds neutral values (`overallScore` and
  `spoofingRiskScore` are `0`, `sensorContributions` and `flags` are empty), and
  `toStr()` prints no `conf=`.
- `proof.spoofingVerdict` is `UNSPECIFIED` (`"UNSPECIFIED"` in JSON).
- `Octet.verify` reports no tier: `ProofVerification.spoofingVerdict` is empty and a
  `requireVerdict` option is ignored (its check reports "not checked").

These fields are deprecated and will be removed in the next major release. The answer
itself (`result`, `level`, `reason`, `achievableLevel`) is unchanged. If you need more
device intelligence or your own scoring logic, Octet offers it as a custom feature or
license.

Disc queries are unaffected: with `OctetConfig.advanced.acceptPlausibleContainment = true` a disc query can return a lower-assurance
`YES`; with it off (the default) it returns `INDETERMINATE` instead. Tight tolerances
only pass with a tight location fix.

---|---|
| `VERIFIED` | Corroborated: independent evidence supports the fix. |
| `PLAUSIBLE` | Lower assurance: the fix is consistent with your query but is **not** independently corroborated. |

An iOS area proof is `PLAUSIBLE` at best in this release. Opt in with
`OctetConfig.advanced.acceptPlausibleContainment = true` to receive a `PLAUSIBLE`
disc; with it off (the default) a disc query returns `INDETERMINATE` rather than
a lower-assurance `YES`, preserving the stricter contract for existing callers.
Tight tolerances only pass with a tight location fix. Gate on the tier that
your use case requires; do not treat the region granularity alone as assurance.

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
enabled server-side, so you will not see these in 2.0.0 yet — wiring the handler
now keeps you ready.)

---

## Privacy manifest

The xcframework bundles a `PrivacyInfo.xcprivacy` declaring the SDK's collected data
types (precise/coarse location, device identifier, usage counters and the daily usage
record) and its
required-reason API usage (System Boot Time for the anchored license clock; UserDefaults
for a one-time device-id migration). Xcode aggregates it automatically into your app's
privacy report at build time. Review it alongside your app's own disclosures when
you complete App Store privacy details. The manifest declares coarse location for
App Functionality and for Analytics, because the diagnostic signals carry region codes.
The 3.0.0 manifest declared App Functionality only; if you ship 3.0.0, declare Analytics
for coarse location in your App Store privacy details yourself.

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

To check the binding on the device instead, pass the same nonce to `Octet.verify` with
`VerifyOptions(expectedSessionNonce: loginNonce)`. The `session-binding` check then fails a proof made
for a different nonce, or for none. Your backend still has to make sure each nonce is
used only once.

---

## Content commitments (new in 3.1.0)

Pass `content` to `isWithin`, `isOutside` or `contains`, and the device signs a commitment to
that content into the proof: each item's key, content type, size and `SHA256(salt ‖ value)`.
The content and the salts stay on the device unless you upload them (see below). A verifier who receives the content can confirm
that this attested device asserted exactly that content at the proof's time and place. The
commitment does not prove that the content is authentic or unedited.

```swift
let video = try await Octet.hashContent(file: videoURL)   // any size, before the call
let verdict = await sdk.loc.isWithin(region: .country(isoCode: "GB"), content: [
    .bytes(key: "note", contentType: "text/plain", Data("valve 7 OK".utf8)),
    .digest(key: "video", contentType: "video/mp4", video),
])
```

- `file(...)` items are hashed in the call up to 64 MiB. Hash larger files with
  `Octet.hashContent` first and pass a `digest` item.
- The SDK salts each item with a random 32-byte salt unless you pass your own. Read it back from
  the item's `salt` (or `ContentDigest.salt`) and keep it with the content. The verifier needs it.
- The SDK hashes exactly the bytes you pass. Strip metadata such as EXIF before you create the
  item, if you want it stripped.
- Content that breaks a rule returns an `invalidCallerContent` verdict with no proof. Without
  location authorization, a query with content returns `permissionRequired`.
- To check a commitment on the device, pass the manifest and content in
  `VerifyOptions.callerMetadata`, and accept the proof only when `verdict == .valid`.
- The manifest is the JSON `{"v":1,"entries":[{"key","contentType","size","salt","sha256"}]}`,
  one entry per item in the order of the proof's `contentCommitments`, with `salt` and `sha256`
  in lower-case hex. Build it from `contentCommitments` and the salts you kept. To check content
  on your backend, use `octet-verify` 1.8.0 or later.
- Caller content is off until Octet enables it for your licence. Until then, a query with
  `content` returns `indeterminate` with reason `callerContentNotEnabled` and no proof. Queries
  without content are unaffected.

### Uploading content to your storage

The SDK can upload the exact bytes it committed to storage you control, for example through a
pre-signed S3, GCS or Azure URL that your backend creates. Octet stores none of the bytes. The
upload starts after the proof is made and never changes it. The proof stays valid whether or
not the upload arrives.

```swift
struct StorageUploads: ContentUploadProvider {
    func uploadTarget(for request: ContentUploadRequest) async throws -> ContentUploadTarget {
        // Ask your backend for a fresh pre-signed URL for this item.
        let url = try await myBackend.presignedPut(proofId: request.proofId, key: request.key)
        return ContentUploadTarget(url: url)
    }
}

// At app launch:
Octet.setContentUploadProvider(StorageUploads())
Octet.setContentUploadListener { status in
    print(status.proofId, status.key, status.state)
}

let verdict = await sdk.loc.isWithin(region: .country(isoCode: "GB"), content: [
    .file(key: "photo", contentType: "image/jpeg", photoURL, upload: true, locator: "site-7/photo.jpg"),
])
```

- Set `upload: true` on a `bytes` or `file` item, or pass `uploadFrom` (the file you hashed) on
  a `digest` item. Items without it are committed only.
- `locator` is an optional label you choose for where the content is kept. The proof lists it
  but doesn't sign it, and your provider receives it. Keep it to 256 bytes. Never put a
  credential, or a URL with a query string, in it.
- The SDK asks your provider for a target before every attempt, so return a freshly signed URL
  each time. `ContentUploadRequest` carries the proof id, key, content type, size, committed
  digest, locator and salt. Store the salt with the file, for example as object metadata. A
  verifier needs it.
- For large files, return `ContentUploadTarget.gcsResumable(sessionUrl:)`,
  `.azureBlock(sasUrl:)` or `.s3Multipart(uploadId:)`. The SDK sends the file in chunks and
  continues after an interruption. For S3 multipart, also implement `s3PartTarget` and
  `s3Complete` in your provider.
- Before each attempt the SDK hashes the content again. If the file changed or is gone, it
  uploads nothing and the item fails with `contentChanged` or `contentMissing`. Keep the file
  unchanged until its upload finishes.
- The listener reports each item's state, `pending`, `uploading`, `uploaded` or
  `failed(reason)`, off the main thread. `Octet.contentUploads(proofId:)` returns the same
  states for one proof. Finished uploads stay listed for 7 days.
- Network errors, `408`, `429` and `5xx` responses, and errors your provider throws are
  retried with backoff, up to 8 attempts within 24 hours. Any other `4xx` fails the item with
  `rejected(httpStatus:)`. When retries run out, the item fails with `providerFailed` if your
  provider kept failing, and with `exhausted` otherwise. An item not uploaded within 7 days also
  fails with `exhausted`. Delivery isn't guaranteed, so check the state before you rely on the
  file being in your storage.
- Uploads run in a background `URLSession`, so iOS keeps sending while your app is suspended.
  Forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to
  `Octet.handleBackgroundUploadEvents(identifier:completionHandler:)`, which returns `false`
  for a session that isn't the SDK's. A retry waits until your app next runs.
- Register the provider early at app launch. Without one, queued uploads wait, for up to 7 days.
- Uploads go straight to the URL your provider returns. A gateway set in `TransportPolicy` and
  its certificate pins don't apply to them, so allow your storage host if you restrict egress.

---

## Keeping your verifier current

If your backend verifies proofs itself with `octet-verify`, upgrade it to
**octet-verify ≥ 1.5.0** before you adopt OctetSDK 3.1.0, which switches
proofs to **semantic-binding v3**. v3 also signs the region a proof was asked about,
so your verifier can read the device's signed inside/outside answer for that region.
A verifier older than 1.5.0 reports the `semantic-binding` check as FAIL for every v3
proof.

1.5.0 is available now and verifies earlier proofs too (v3, then v2, then v1), so
upgrading ahead of time is safe. The SDK's own `Octet.verify` already handles v3.

**The signed tier on your backend.** The tier is still signed inside the proof bytes, and octet-verify
≥ 1.6.0 can enforce it with `--require-verdict verified` (or `plausible`). On the device,
`Octet.verify` reports and enforces it only where the tier is enabled for your licence (see
"Confidence score and assurance tier").

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

Near a border between two subdivisions, a device whose accuracy area crosses that border
can only be proven at the country level. A subdivision query returns `indeterminate` with
`insufficientPrecision` and `achievableLevel` `.country`, and a proof of the device's own area
claims the country only. A policy that accepts only one of the two subdivisions will see
such a device as unknown, not as inside or outside. Plan for that answer near
subdivision borders, for example by asking again once the device has a better fix.

---

## Log output

A released SDK writes only lines you can act on to the device log. They go
through `OSLogSink`, which forwards into Apple's unified logging system with
the tag as the category:

| Tag | Level | When |
|---|---|---|
| `OctetLicense` | info | Every `Octet.start`: which license mode it took: `sandbox` when `sandboxBypassToken` is set, `attested` otherwise. An attested app lands on release when App Store or TestFlight signed, on sandbox when development signed. |
| `OctetLicense` | warn | The SDK version is deprecated, or the license stops working within 30 days. |
| `OctetLicense` | error | `Octet.start` threw a `LicenseError`. Names the case and what to fix. |
| `SandboxBootstrap` | warn | A simulator or provisioned build carries a `sandboxBypassToken`, which an App Store build will refuse. |

Set `OctetConfig.advanced.logLevel` to `.warn` or `.error` to quiet the lower
lines. None of these lines carry coordinates, device identifiers or your
sandbox token. `OSLogSink` marks the message text `.private`, so Xcode's
console shows it while the debugger is attached and Console.app shows
`<private>` otherwise. To route the lines into your own pipeline, implement
`LogSink` and register it with `PublicLog.shared.addSink(_:)`.

The SDK's internal diagnostic stream is compiled to reach the device log only
in a debug build of the SDK. The released xcframework never writes it.

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
`.sigstore.json` build-provenance bundle is attached to the release. Current releases
ship **without** one, so skip step 3 if no bundle is present. Steps 2–3 use the attached files offline —
the GitHub CLI and cosign are needed, but no special repository access.

---

## Reference implementation

The sample app in [`sample/`](sample/) exercises the minimum viable
permission flow if you need a reference.

---

## Updates to this document

Updates to this document arrive with each SDK release. Re-check it
when upgrading.

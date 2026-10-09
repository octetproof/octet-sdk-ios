# Changelog

All notable changes to the OctetSDK for iOS are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [3.0.0] — 2026-10-09

> Major release, in lockstep with Android 3.0.0. Three changes alter what an existing
> integration sees, so read _Changed (breaking)_ before upgrading. The SDK now sends one
> usage record per device per day. Location claims follow real borders, so US territories
> claim their own country and a device close to a border can get `regionUnresolved`. A
> pinned `claimedRegion` must be an assigned ISO 3166 code. The main addition is
> `TransportPolicy`, which routes every SDK network call through a gateway you choose.

### Changed (breaking)

- **Usage reporting is always on: one record per device per day.** After the first
  proof of each UTC day the SDK sends one `device_active` usage record with the next
  background heartbeat, so Octet can count active devices for billing. It carries no
  location, no proof data, no user or account identity and no new device identifier,
  and it never blocks or delays a proof. `OctetConfig.creditServiceUrl`, previously a
  reserved opt-in hook, now defaults to `https://credits.octetproof.com` and only
  overrides the endpoint for testing. Leaving it unset no longer disables anything.
  New: `OctetConfig.defaultCreditServiceUrl` and the optional `CreditStatus.reason`.
  See "Usage reporting" in INTEGRATION.md.
- **US territories claim their own country.** A device in Puerto Rico, Guam, the US
  Virgin Islands, American Samoa, the Northern Mariana Islands or the US Minor Outlying
  Islands now claims that territory's ISO 3166 code (`PR`, `GU`, `VI`, `AS`, `MP`, `UM`).
  `isWithin(.country("US"))` answers `NO` there. To accept those users, add the territory
  codes to your region list.
- **Country and state claims follow real borders.** The SDK claims a country or a state
  only when the device is clearly inside it. Close to a border, or when the location fix
  is too coarse to tell, a country or state query returns `INDETERMINATE` with
  `regionUnresolved` where 2.0.0 answered `YES` or `NO`. State claims now also work
  outside the US, starting with Ukraine and Russia. Crimea, Sevastopol, Donetsk, Luhansk,
  Zaporizhzhia and Kherson always claim `UA`.
- **A pinned `claimedRegion` must be an assigned ISO 3166 code.** A code that is
  malformed or not assigned produces no proof (`regionUnresolved`). 2.0.0 signed it.

### Added

- **`TransportPolicy` (`OctetConfig.advanced.transport`): choose where the SDK's network
  calls go.** `.direct` (the default) is unchanged. `.integratorGateway` sends every
  first-party call, and the SDK's third-party lookups, through one HTTPS host you run.
  `.octetGateway` sends them through `gw.octetproof.com`. Options:
  - `thirdParty`: `.proxy` (default) sends third-party lookups through the gateway.
    `.disable` skips them in any mode, and a proof is still produced.
  - `pins`: SPKI pins for the app-to-gateway TLS connection. Pin a stable intermediate
    or root, not an auto-rotating leaf. `pins` is ignored in `.octetGateway`.
  - `fallbackToDirect` (default `false`): after repeated gateway failures, critical calls
    go direct until the gateway recovers.
  - `osAttestationInGatewayModes` (default `true`): `false` skips per-proof App Attest in
    gateway modes, so proofs are marked un-attested.
  - `borderDataUpdates` (default `true`): see the border-data entry below.

  In a gateway mode, country and state lookups go to `{gateway}/ext/geo/reverse` instead
  of the OS geocoder. Your gateway must forward that route, or country proofs return
  `INDETERMINATE` unless `fallbackToDirect` is on. The full route table and reference
  nginx, Cloudflare and AWS configs are in INTEGRATION.md.
- **Signed border-data updates.** At most once a day the SDK checks for a newer border
  map, verifies its signature, and uses it if it is newer than the bundled one. Turn it
  off with `TransportPolicy.borderDataUpdates = false`. The bundled border map adds about
  2.6 MB to the SDK.
- **`Octet.verify` reports and enforces the signed verdict tier.** A disc answer verifies
  whether it was signed `VERIFIED` or `PLAUSIBLE`. New: a `verdict-tier` check on disc
  answers, `VerifyOptions.requireVerdict` (fails a proof below the tier, and fails closed
  when the verdict is not signed into the proof), and `ProofVerification.spoofingVerdict`.
  Matches octet-verify 1.6.0's `--require-verdict`.
- **`BootstrapReason.newDevicesBlocked`: a typed startup failure when a free account
  accepts no new devices.** It carries a server-signed upgrade link (`upgradeUrl`). Open
  it verbatim and never build one. Devices that already activated are unaffected.
- **Opt-in `PLAUSIBLE` containment (`OctetConfig.advanced.acceptPlausibleContainment`,
  default off).** With the flag on, `contains(...)` and `isWithin(.disc(...))` can return
  `YES` or `NO` from a `PLAUSIBLE` proof, not only from a `VERIFIED` one. With the flag
  off, a disc query stays `INDETERMINATE` unless the proof is `VERIFIED`.
- **`LocationProof.spoofingVerdict`**: the proof's assurance tier (`VERIFIED`,
  `PLAUSIBLE`, ...), readable directly and in `proof` JSON as `spoofing_verdict`, without
  decoding the proof bytes. Read it, not the region granularity, to decide what a `YES`
  is worth. See INTEGRATION.md.
- If you verify proofs yourself with `octet-verify`, run 1.5.0 or later.

### Changed

- **Direct mode uses `ipwho.is` for IP location instead of `ipapi.co`.** Add `ipwho.is`
  to any network allowlist, or set `TransportPolicy.thirdParty = .disable`.
- **A fresh proof right after `Octet.start` waits for the SDK to finish starting** (up to
  30 s) instead of returning `noFix`. Allow for this if your app applies its own timeout
  to the first call.
- **On a fresh install, `Octet.start` can take a few seconds longer** while it retries
  the first remote-configuration fetch.
- `achievableLevel` reports `subdivision`, never `city`, when the fix is too coarse for
  the requested level.
- A cached activation is reused only with the same licence and server. Starting offline
  with an activation from a different licence or server fails with `noActivation`.

### Security

- **Updated the built-in TLS pins** for `api.octetproof.com` and `gw.octetproof.com`. If
  you turned on `enableCertPinning` with 2.0.0, upgrade to 3.0.0.
- Release builds of the SDK no longer write diagnostic logs.

### Fixed

- US state-level proofs resolve correctly, including state queries made from outside
  the US.
- Background state-level proofs carry the device's country.
- On-demand proofs always use the current location.
- Proof generation no longer stalls when several requests overlap.
- Fewer proofs are refused for people on the move, on foot or by train, car, bus or
  bicycle.
- A sandbox session signs in again by itself when its sign-in expires, and works with a
  debugger attached. A blank `sandboxBypassToken` is treated as unset.
- The public sample app builds in the Release configuration again.

## [2.0.0] — 2026-09-09

> Major release, in lockstep with Android 2.0.0. Two things make it major.
> First, **how the SDK activates has changed**: at `Octet.start` it now proves the
> running app instance with **Apple App Attest** and obtains its licence by
> attested bootstrap, replacing the pasted-license-key activation step. Second, the
> proof surface grows — a public on-device **verifier** (`Octet.verify`), a public
> teardown (`OctetSdk.close()`), a cache-bypass (`forceFresh`) — and
> **semantic-binding v2 becomes the default proof form**. **Read _Changed (breaking)_ before upgrading:** beyond the
> activation change, one JSON flag spelling changed, and two verdicts now refuse
> where they previously returned a misleading positive.
>
> _Released 2026-09-09._

### Changed (breaking)

- **Attested activation replaces the license-key flow.** `Octet.start` no longer
  activates by sending a pasted license key to an activation endpoint. It now
  proves the running app instance with **Apple App Attest** and bootstraps its
  licence from the backend. A host that cannot attest — the simulator, CI, or a
  locally built debug app — sets `OctetConfig.sandboxBypassToken` and bootstraps
  through the sandbox path instead; a device with neither attestation nor a sandbox
  token fails closed. `OctetConfig.licenseKey` remains a field for now but is no
  longer the credential that activates the SDK. **This is an integration-level
  change:** an app that relied on a license key alone must be provisioned for App
  Attest (or carry a sandbox token for non-device builds).

- **`confidence.flags` values in `toJson()` / `toJsonl()` are now `UPPER_SNAKE`.**
  iOS emitted Swift case names where Android emitted upper-snake, in an output
  documented as wire-stable — so the same flag read differently depending on which
  platform produced it.

  | Before (iOS) | Now (both platforms) |
  |---|---|
  | `unspecified` | `UNSPECIFIED` |
  | `vpnActive` | `VPN_ACTIVE` |
  | `airplaneMode` | `AIRPLANE_MODE` |
  | `uncertaintyHigh` | `UNCERTAINTY_HIGH` |

  **Migration:** affects only callers parsing `toJson()` / `toJsonl()` on iOS. The
  typed `ConfidenceSummary.flags` is unchanged, as is `toStr()`. Android is
  unaffected — it already emitted these spellings.

### Added

- **`Octet.verify(...)` — public on-device proof verification.** An offline
  verifier that checks a proof's signature, freshness, semantic binding, and
  hardware-attestation anchoring, and returns a grouped, human-readable result
  naming every check that ran and every check that could not — and why. It makes no
  network call and needs no backend, so a relying party can reach a local trust
  decision, or triage a proof before forwarding it. The authoritative end-to-end
  verifier remains the standalone `octet-verify` CLI; `Octet.verify` runs the same
  checks in-process.

- **Hardware-attestation anchoring in the verifier.** `Octet.verify` can anchor a
  proof's device key to the platform hardware root — Apple's App Attest root — so a
  verified proof carries evidence it came from a genuine app instance on genuine
  hardware, not merely that its signature checks out.

- **`OctetSdk.close()` — public teardown.** Stops all SDK activity — location
  monitoring, the background heartbeat, any in-flight upload — and releases the
  handle, so a host that needs the SDK for only part of its lifecycle can shut it
  down cleanly rather than leave it running. Idempotent.

- **`forceFresh` on `isWithin` / `isOutside` / `contains`.** An optional flag that
  bypasses the short-lived proof-reuse cache and forces a freshly measured proof
  for this call — for a caller that needs a just-now measurement rather than a
  buffered one. Omitted (the default), behaviour is unchanged: the cache is
  consulted.

- **`regionFromJson`.** The inverse of `OctetRegion.toJson()` / `toJsonl()`:
  decodes the same stable tagged shape the forward direction emits, round-tripping
  every factory. It exists so a non-native caller — React Native, a server payload,
  a stored region — can hand a region across a language boundary without
  re-modelling seven shapes on the far side.

  Input is treated as untrusted, so unlike the region factories it always throws
  `OctetRegion.DecodeError` on malformed, missing, wrong-typed or out-of-range
  input, and never traps. `disc` has no tag of its own (it round-trips through
  `ellipse`), and H3 cells are hex strings rather than JSON numbers, because an H3
  index exceeds the exact-integer range of a JSON number.

- **`decisionRef` on `isWithin` / `isOutside` / `contains`.** An optional opaque
  decision identifier (host-minted, ≤256 chars) that binds a generated proof to one
  specific authorization decision, letting a relying party fetch and trust a proof
  for exactly that decision. Additive and backwards-compatible: the default `nil`
  is unchanged behaviour and the upload envelope stays `schema_version: 2`.

- **Remote configuration — `sdk.flags`.** A read-only surface: `getBoolean` /
  `getInt` / `getString(key, default)` and `getAssignment(experiment)`, backed by a
  signed bundle fetched at `start()` and refreshed on each heartbeat, cached
  last-good. Default-on via `OctetConfig.flagsEnabled`. Entirely fail-safe — a
  disabled subsystem, no bundle, or an unknown or wrong-typed key all return the
  default you supplied.

- **New refusal reason `regionUnresolved`.** Returned when a region genuinely
  cannot be resolved at the required confidence — an honest "couldn't measure",
  deliberately distinct from a detected spoof.

### Changed

- **semantic-binding v2 is now the default proof form.** A proof now binds its
  semantic fields — level, region type, integrity status, and the position-
  commitment geometry — under the v2 scheme by default, hardening it against
  post-hoc field edits. A current `octet-verify` accepts both the v1 and v2 forms;
  verifying a v2 proof needs an up-to-date verifier.

- **The App Attest assertion binds the Secure-Enclave signing key.** The iOS App
  Attest assertion now commits to the device's Secure-Enclave signing key, tying
  the attested app instance to the exact key that signs its proofs.

- **Telemetry hardened.** The optional anonymous usage counters — on by default, no
  location data, unchanged in shape since 1.1.0 — are now encrypted at rest on the
  device, their upload sample rate can be tuned by remote configuration, and a
  fresh install no longer uploads a report before its first activity. Disable all
  of it with `OctetConfig.telemetryEnabled = false`.

- **A country or subdivision proof now claims where the device *is*, not what was
  *queried*.** `isWithin(country("XX"))` previously stamped the queried region into
  the proof's claim, which made a decision-bound country predicate able to answer
  only `YES`. The claim is now derived from the estimate, with granularity clamped
  to the query — never finer, so no street-level geometry leaks out of a country
  predicate — and decision binding moves entirely onto `challenge_decision_ref` and
  `region_ref`.

  **Expect more refusals at first.** A country-level decision whose honest claim
  differs from the queried country now fails closed. That is the intended
  behaviour, not a regression: the previous answer was tautological.

### Security

Brief — each hardens a case that previously produced a misleading positive:

- **A software-simulated location is refused, not proven** — such a fix now yields
  `INDETERMINATE` with `mockLocationDetected`, never a positive proof. An external
  GPS accessory is still treated as legitimate.
- **An unavailable cross-check no longer counts as agreement** — a corroborating
  signal that cannot be measured is recorded as unverifiable, not as confirmation.
- **Refusal reasons distinguish adversarial from benign** — a detected spoof
  carries an adversarial reason (`mockLocationDetected`, `spoofingDetected`,
  `tampering`, `attestationFailed`), machine-distinguishable from the benign
  couldn't-measure reasons, so a policy layer can treat them differently.
- **IP geolocation is no longer promoted to a country anchor** — an IP-derived
  country no longer stands in for a measured one.

### Fixed

- **`toJson()` / `toJsonl()` now emit the real proof.** Both platforms emitted a
  placeholder in place of `proof` and `confidence`, so a JSON consumer received a
  `YES` verdict carrying no proof bytes at all. `proof` now carries `id`, `level`,
  `timestamp_ms`, `sdk_version`, `platform`, `confidence`,
  `position_commitment_b64` and `proof_bytes_b64`, and `achievable_level` is now
  emitted at the top level. `claimedRegion` stays absent — it already travels
  inside the proof bytes. No typed API change.

- **A decision-bound call no longer returns a proof minted without that decision.**
  `isWithin` / `isOutside` / `contains` with a `decisionRef` could return a
  buffered, non-decision-bound proof, so no decision-scoped proof was ever
  uploaded and a relying party's fetch-by-decision found nothing and denied. The
  freshness buffer is now consulted only when neither a session nonce nor a
  decision reference is set.

- **`Octet.start` no longer stalls the main thread during device attestation.** The
  attestation step now runs off the main actor, so a slow attestation can no longer
  cause an app-not-responding hang at launch.

- **The first proof upload after a fresh activation is reliable.** A transient
  device-identity mismatch that could make the very first upload retry once before
  succeeding is resolved, so the first proof uploads cleanly.

- **The activation bearer is refreshed against its real expiry.** The SDK assumed a
  ~24 h window against a backend token that actually lives ~1 h, so authenticated
  calls could be rejected with `401` after the first hour of a session. The SDK now
  honours the token's real expiry, treats it as expired 30 s early, and refreshes
  at a cadence derived from that lifetime. Sessions established before this change
  fall back to the previous behaviour, so upgrades are seamless.

## [1.2.1] — 2026-08-03

> **Security hotfix, released in lockstep with Android 1.2.1.** No new features and
> **no change to the proof wire format, proof semantics, trust levels, or verdict
> codes** — a 1.2.1 proof means exactly what a 1.2.0 proof means. The binary
> hardening in 1.2.1 is Android-specific (the iOS framework is pure Swift); iOS ships
> 1.2.1 to stay version-aligned and to remove `OctetConfig.debugMode`. **All consumers
> should upgrade**; 1.0.0 / 1.1.0 / 1.2.0 are deprecated.
>
> _Release date stamped at tag time._

### Removed (breaking)

- **`OctetConfig.debugMode` (added in 1.2.0).** Removing it restores the safe default
  in which a released SDK does not surface internal diagnostics through the host app.
  **Breaking** for anyone who set it — the field existed for only one release.

### Deprecated

- **All releases before 1.2.1 are deprecated in favour of 1.2.1** — the four
  `0.0.x-alpha` previews and `1.0.0`, `1.1.0`, `1.2.0`, released in lockstep with
  Android 1.2.1. Their downloadable artifacts have been **removed from the GitHub
  release pages** for security; a build pinned to an old version must move to
  **≥ 1.2.1**.

## [1.2.0] — 2026-07-29

> Feature release on top of 1.1.0. Backwards-compatible, drop-in upgrade: the
> public API additions are additive and the proof wire format is a strict superset
> of 1.1.0 — a proof made without a session nonce is byte-identical, and the new
> optional session-binding stage is ignored (NOT-CHECKED) by a 1.1.0 verifier.
> **Enforcing** session-binding needs octet-verify ≥ 1.2.0. Two other additions
> ship **inert** (SDK-version upgrade gating; the `creditServiceUrl` hook) —
> present but with no runtime effect until their backends turn them on — so
> upgrading changes nothing for existing integrations.

### Added

- **Verifier hardware-root bootstrap — `Octet.attestationEnrolmentBundle()`.**
  Returns this device key's `AttestationEnrolmentBundle` (`jsonString()` /
  `protoData()`), carrying the App Attest object, its nonce, and a matching
  assertion. Hand it to a verifier's enrolment step so the verifier can establish
  this device's hardware root **without** waiting for the once-per-key attestation
  object to arrive on a submitted proof — useful for a freshly-deployed, scaled,
  or migrated verifier. Cheap and local (a Keychain read, no network); returns
  `nil` until the device key has been attested (first proof of the install).
- **SDK version reporting + upgrade gating.** The SDK now reports its version and
  platform on every backend request. Two new surfaces:
  `LicenseError.upgradeRequired(minVersion:message:)`, thrown from `Octet.start`
  when the backend rejects an out-of-support version; and non-fatal soft-warning
  hints on `LicenseStatus` — `upgradeRecommended: Bool` and
  `minSupportedVersion: String?`. **Inert in 1.2.0** — the backend gates no version
  yet, so you will not see these until version policy is enabled.
- **`OctetConfig.creditServiceUrl` (reserved).** Opt-in endpoint for a forthcoming
  credit-consumption subsystem. Default `nil` disables it; **metering is not active
  in this release.**
- **Privacy manifest.** The xcframework now bundles a `PrivacyInfo.xcprivacy`
  declaring collected data types (location, device identifier, aggregate usage
  counters) and required-reason API usage. Xcode aggregates it into your app's
  privacy report automatically. See INTEGRATION.md → "Privacy manifest."
- **`OctetConfig.debugMode`.** New opt-in config field (default `false`). When
  `true`, the SDK unlocks its verbose diagnostics-capture tier in a **release**
  build for a support deep-dive — previously only available in a debug build of
  the SDK. Client-side only; PII discipline unchanged.
- **Session-binding for logins.** `isWithin` / `isOutside` / `contains` gain an
  optional `sessionNonce: Data?`. Pass the one-time nonce your login backend issued
  and it's committed inside the signed proof, so your verifier can confirm the proof
  was made *for that specific login*; forward the returned `verdict.proof` to your
  backend. Only a hash of the nonce is serialized (never the raw bytes); omitting it
  preserves 1.1.0 behaviour exactly. Enforcement needs octet-verify ≥ 1.2.0.

### Changed

- **Stronger GNSS anti-spoofing.** The raw-GNSS witness that cross-checks the OS
  location provider is now fully functional and degrades honestly on weak signal,
  improving spoof resistance for on-Earth proofs. No change to the proof wire
  format or public API.
- **Rolling license-token persistence.** The SDK persists the refreshed license
  token returned on lease responses, so a device holds a fresh token across
  restarts within the offline-grace window.

### Build & distribution

- Releases now publish **SHA-256 checksums** and **SLSA build provenance**, an
  **SBOM**, and a **keyless cosign signature** for the xcframework. See the
  "Verifying the download" section in `INTEGRATION.md`.

## [1.1.0] — 2026-06-25

> Feature release on top of 1.0.0. Backwards-compatible, drop-in upgrade: the
> public API additions are additive and the proof wire format stays compatible
> (existing proofs remain valid).

### Added

- **Device attestation.** Proofs now carry an Apple App Attest assertion bound
  into the signed proof chain, so a verifier can confirm a proof came from a
  genuine app instance on a genuine device. Cadence is configurable via
  `OctetConfig.advanced.attestationCadence` (per-session / periodic / per-proof).
- **Anti-replay protection for uploaded proofs.** Each uploaded proof carries a
  server-issued, single-use upload nonce and a replay-control binding, so the
  backend can reject duplicated or replayed uploads. Proofs generated offline
  still upload and remain valid.
- **Semantic field binding.** A proof's level, region type, and integrity status
  are cryptographically bound into the proof chain and can't be altered after the
  fact without invalidating the proof.
- **Optional usage telemetry.** Aggregated, privacy-preserving usage counters
  (no location data) reported to the license backend. On by default; disable with
  `OctetConfig.telemetryEnabled = false`. Counters are buffered encrypted on
  device and uploaded at most once a day.
- **`OctetVerdict.achievableLevel` + clearer reason codes.** When the SDK can't
  produce a proof at the requested precision, the verdict reports the level it
  *can* reach, plus reason codes that separate a benign precision shortfall
  (`insufficientPrecision`) from a security refusal (`spoofingDetected` /
  `tampering`).

### Changed

- When a location can't be proven at the requested precision, the SDK now returns
  an `indeterminate` verdict carrying the achievable level instead of silently
  emitting a coarser proof — your app decides any fallback.

### Fixed

- Proof uploads no longer stall after an activation lease expires during an
  offline grace period; the SDK re-activates and resumes.
- Warm-start reliability: a stale activation token is refreshed before the first
  proof upload after launch.

## [1.0.0] — 2026-06-11

> **First stable release.** The public API, proof wire format, and license-
> claim schema are committed to under semantic versioning from this release
> forward — backwards-compatible changes ship as 1.x.x. Drop-in upgrade
> from 0.0.4-alpha for consumers using the documented public API.

### Stable surfaces

- **Public API** — `Octet.start(...)`, the `sdk.loc.isWithin(...)` predicate
  surface, `OctetVerdict`, `LicenseStatus`, `OctetRegion` shapes, the
  `LocationProof` envelope, and supporting value types in the `OctetSDK`
  module.
- **Wire format** — `LocationProof` envelope (slim public proto with
  opaque `proof_bytes` plus curated public fields), license PASETO v4.public
  claim schema, activation lease shape.
- **Distribution channels** — SwiftPM + Carthage.

### Changed — public API surface narrowed

The 1.0 build narrows the visible surface to the documented public API.
Consumers using the public `Octet` API are unaffected. Consumers who had
imported other symbols will see "no such type" on rebuild — those symbols
are not part of the supported surface.

Surfaces that are public from 1.0:
- `DeviceKeySecurityLevel` (`HARDWARE_STRONGBOX` / `HARDWARE_TEE` /
  `SOFTWARE`) — surfaced via the attestation chain so relying parties can
  read the device-key tier per proof.
- `LogSink` + `LogLevel` + the platform default sink (`OSLogSink`) —
  implement `LogSink` to route SDK logs into your own pipeline.

### Fixed

- Clean SwiftPM consumers of the published xcframework no longer hit
  `Unable to resolve module dependency: SwiftProtobuf` at build time; the
  binary distribution is now self-contained.

### Carry-over from 0.0.4-alpha

If you're upgrading from 0.0.3-alpha or earlier, the 0.0.4-alpha entry
below details the security-hardening pass: opt-in TLS public-key pinning,
hardware-backed key storage, fail-closed proof verifier, default-private
logging, hardened URL validation, and a magnetometer-based liveness signal
added to on-Earth proof confidence. All carry forward unchanged.

## [0.0.4-alpha] — 2026-06-11

> **Security-hardening pass.** Every change is opt-in or fail-safer-
> by-default; the public API surface is unchanged. Drop-in upgrade
> from 0.0.3-alpha.

### Added

- **Opt-in TLS public-key pinning** for connections to
  `api.octetproof.com`. Off by default in this release; enable via
  the SDK's networking configuration. Pin set covers the current
  certificate-authority intermediate and a backup pin; pin expiry is
  tracked.
- **Magnetometer-based liveness signal** is now incorporated into
  on-Earth proof confidence (alongside existing motion / GPS
  signals).
- `DeviceKeySecurityLevel` value exposed on the hardware-attestation
  surface, reporting the actual storage tier
  (`hardwareSecureEnclave` / `software`) for the device key used in
  the current run.

### Changed — defaults

- **Unified-log privacy hardened.** Internal log call sites now treat
  free-form interpolations as `.private` by default; tags remain
  `.public`. Release builds no longer surface message bodies through
  `Console.app` / `log show` without explicit privacy opt-in.
- **Keychain items** for the device key, activation bearer, and
  device-id are written with `SecAccessControl` requiring
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (or stricter on
  hardware-backed devices). Items are no longer included in iCloud
  Keychain backups or device-to-device transfer.
- **On-device proof verifier fails closed.** The on-device verifier
  now returns an explicit `VerificationStatus` of
  `verified` / `shapeValidUnverified` / `invalid`, with `isValid` set
  only when the signature has been cryptographically verified against
  a trusted key. The authoritative end-to-end verifier remains the
  standalone `octet-verify` CLI.
- **Proof-upload URL validation** tightened. The LAN-HTTP exception
  (RFC 1918 + loopback, when proof-upload is opt-in pointed at a
  development backend) now uses strict numeric-literal parsing rather
  than DNS-resolving string-prefix matches.

### Sample app

- Sample renamed from `OctetV1Toy` to `OctetSample`; SwiftPM target,
  scheme, and bundle ID (`com.octetproof.sample`) updated. The xcodeproj
  is generated from `project.yml` via XcodeGen.
- Sample `Info.plist` usage strings rewritten to neutral, end-user-
  appropriate copy.

## [0.0.3-alpha] — 2026-06-09

> **Proof upload + heartbeat lease refresh.** Opt-in proof upload to an
> `octet-proofs` backend, hardware-backed activation-bearer cache, and
> a periodic heartbeat scheduler. Backwards-compatible with 0.0.2-alpha
> consumers — the new features are gated on a new `proofUploadUrl`
> field that defaults to `nil` (upload subsystem entirely disabled).

### Added — proof upload

- `OctetConfig.proofUploadUrl: String?` — opt-in proof-upload endpoint.
  Default `nil`: upload subsystem disabled entirely (no scheduler, no
  network calls). When set, the SDK uploads each generated
  `LocationProof` to your configured `octet-proofs` backend. HTTPS-only,
  with a LAN-HTTP exception (RFC 1918 + loopback) for local development.
- Authentication, retry-with-backoff, and queuing across app restarts
  are handled by the SDK — nothing additional to wire up.

### Added — heartbeat scheduler + activation-bearer cache

- The activation bearer issued at `/v1/activate` is now persisted in
  Keychain (`ThisDeviceOnly`) so the SDK can refresh license leases and
  authenticate proof uploads across app restarts without re-activating.
- A background scheduler performs periodic lease-refresh pings at the
  cadence the activate response specifies. The device fingerprint stays
  consistent across restarts.

### Independent verifier

- The independent proof verifier is now its own repository:
  [`octetproof/octet-verify`](https://github.com/octetproof/octet-verify).
  It verifies a proof from a file or by fetching from a backend, and
  prints what was and was not validated. Designed to be auditable end-
  to-end by anyone integrating against the SDK.

### Documented

- New section in `INTEGRATION.md` on proof-upload data handling — what
  the SDK transmits when upload is enabled, how long uploaded proofs
  are retained on the Octet-hosted backend, the option to fetch and
  persist proofs yourself, and the self-hosted backend configuration.

### Sample app

- Sample updated to demonstrate proof upload against the configured
  activation backend.

## [0.0.2-alpha] — 2026-06-04

> **v1 license-key cutover.** Wire-breaking: v0-alpha tokens issued
> before this release will not verify against the v1 verifier.
> Existing customers receive re-issued v1 tokens.

### Changed — license model (wire-breaking)

- New v1 PASETO v4.public claim schema (`iss, iat, nbf, exp, lid, sub,
  jti, typ, v, prod, pver, plat, tier, model, limits, feat, ehash,
  meta`). Tolerant-reader on unknown claims; fail-closed defaults; 60s
  skew tolerance on `nbf` / `exp`.
- New `LicenseError.verificationFailed(reason:)` carrying a
  `VerificationReason` value that names the specific failure mode
  (vendor prefix, signature, validity window, schema mismatch,
  product/platform mismatch, clock rollback). The other
  `LicenseError` cases (`malformedKey`, `expired`,
  `activationWindowClosed`, `revoked`, `network`, `noActivation`,
  `serverRejected`) are unchanged.
- Activation flow: `/v1/activate` now returns a plain JSON lease (TLS
  is the integrity layer); no more signed PASETO activation tokens.
  `ActivationClient` exposes `activate` / `heartbeat` / `deactivate`.
  14-day offline grace after a successful activation.
- Stable device-fingerprint formula:
  `b64url(sha256(install_uuid || platform_hint))` where
  `platform_hint` is `UIDevice.current.identifierForVendor`.
- Anti-rollback clock: `AnchoredClock` persists server-
  timestamp anchors in Keychain (`ThisDeviceOnly`), raises
  `.clockRollback` when the wall clock regresses past tolerance.

### Removed

- The v0-alpha activation-token PASETO shape (`ActivationClaims` /
  `octet.activation` typ). v1 activation returns plain JSON.
- `Octet.start`'s old `sdkVersion` + `appId` activate-time claims —
  token + device fingerprint are the v1 auth surface.

### Sample app

- `LocalConfig.swift.example` gains an `activationServerUrl` field
  (defaults to `https://api.octetproof.com`; override to a LAN
  address when running against a self-hosted activation backend).

### Deprecated

- **[0.0.1-alpha](https://github.com/octetproof/octet-sdk-ios/releases/tag/0.0.1-alpha)
  is deprecated.** Tokens from the current production backend will
  fail to verify on 0.0.1-alpha with
  `LicenseError.verificationFailed(.unsupportedSchema)` at
  `Octet.start`. Upgrade to `0.0.2-alpha` or later.

## [0.0.1-alpha] — 2026-05-28

First public release. Pre-stable: API, naming, and on-disk surface may
still change without notice across `0.0.x`.

### License model

License keys are valid for 90 days from issuance, followed by a 15-day
grace window (the SDK keeps working and surfaces a renewal nudge via
`LicenseStatus.state == .gracePeriod`), then a hard stop at 105 days.
There is no per-device activation cap — a license is bound to its
holder, not to a specific device install.

### SDK distribution

- Public `OctetSDK` module shipped as a binary `OctetSDK.xcframework`,
  statically linking SwiftProtobuf so consumers see no extra SwiftPM
  transitive dependencies.
- Single module name across distribution channels: SwiftPM and Carthage
  consumers both write `import OctetSDK`.

### Public API

- `Octet.start(config:startPosition:)` async entrypoint; license
  verification + first-run activation against
  `api.octetproof.com/v1/activate`, activation token cached in Keychain.
- Predicate API `sdk.loc.isWithin(region:atTime:)` with `OctetRegion`
  shapes (country, polygon, circle) and structured `OctetVerdict`
  (result / reason / message / optional cryptographic proof).
- License + activation envelopes use PASETO v4.public.

### Known limitations in 0.0.1-alpha

- The xcframework is **unsigned**. Apple recommends signing since
  Xcode 15; consumers will see a signing-status warning but the
  framework is functionally usable. Codesigning lands when the paid
  Apple Developer Program cert is provisioned.

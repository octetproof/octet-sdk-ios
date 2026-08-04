# Changelog

All notable changes to the OctetSDK for iOS are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

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
  the SDK. Client-side only; PII discipline unchanged. (#163)
- **Session-binding for logins.** `isWithin` / `isOutside` / `contains` gain an
  optional `sessionNonce: Data?`. Pass the one-time nonce your login backend issued
  and it's committed inside the signed proof, so your verifier can confirm the proof
  was made *for that specific login*; forward the returned `verdict.proof` to your
  backend. Only a hash of the nonce is serialized (never the raw bytes); omitting it
  preserves 1.1.0 behaviour exactly. Enforcement needs octet-verify ≥ 1.2.0. (#128)

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

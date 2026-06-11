# Changelog

All notable changes to the OctetSDK for iOS are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.0.4-alpha] — 2026-06-11

> **Security-hardening pass.** Every change is opt-in or fail-safer-
> by-default; the public API surface is unchanged. Drop-in upgrade
> from 0.0.3-alpha.

### Added

- **Opt-in TLS public-key pinning** for connections to
  `api.octetproof.com`. Off by default in this release; enable via
  the SDK's networking configuration. Pin set covers the current
  certificate-authority intermediate and a backup pin; rotation
  procedure is documented internally and pin expiry is tracked.
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

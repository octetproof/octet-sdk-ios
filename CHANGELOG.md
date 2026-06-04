# Changelog

All notable changes to the OctetSDK for iOS are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.0.2-alpha] — 2026-06-04

> **v1 license-key cutover.** Wire-breaking: v0-alpha tokens issued
> before this release will not verify against the v1 verifier.
> Existing customers receive re-issued v1 tokens.

### Changed — license model (wire-breaking)

- New v1 PASETO v4.public claim schema: `iss, iat, nbf, exp, lid, sub,
  jti, typ, v, prod, pver, plat, tier, model, limits, feat, ehash,
  meta`. Tolerant-reader per spec R1; fail-closed defaults per R2; 60s
  skew tolerance on `nbf` / `exp`.
- New `LicenseError.verificationFailed(reason:)` carrying a
  `VerificationReason` enum (`badVendorPrefix, unknownKid,
  badSignature, notYetValid, wrongIssuer, wrongTyp, unsupportedSchema,
  productNotLicensed, platformNotLicensed, clockRollback`). The other
  `LicenseError` cases (`malformedKey`, `expired`,
  `activationWindowClosed`, `revoked`, `network`, `noActivation`,
  `serverRejected`) are unchanged.
- Activation flow: `/v1/activate` now returns a plain JSON lease (TLS
  is the integrity layer); no more signed PASETO activation tokens.
  `ActivationClient` exposes `activate` / `heartbeat` / `deactivate`
  per the v1 spec. 14-day offline grace after a successful activation.
- New device fingerprint per spec §13:
  `b64url(sha256(install_uuid || platform_hint))` where
  `platform_hint` is `UIDevice.current.identifierForVendor`.
- Clock anti-rollback per spec §11: `AnchoredClock` persists server-
  timestamp anchors in Keychain (`ThisDeviceOnly`), raises
  `.clockRollback` when the wall clock regresses past tolerance.
- New v1 production signing kid `octet-2026-05-f99d` embedded in the
  registry. Pre-rotation kid `octet-2026-05-62f1` retained for token
  continuity (still resolves a public key, but its tokens fail the v1
  schema gate).

### Removed

- The v0-alpha activation-token PASETO shape (`ActivationClaims` /
  `octet.activation` typ). v1 activation returns plain JSON.
- `Octet.start`'s old `sdkVersion` + `appId` activate-time claims —
  token + device fingerprint are the v1 auth surface.

### Sample app

- `LocalConfig.swift.example` gains an `activationServerUrl` field
  (defaults to `https://api.octetproof.com`; override for LAN-backend
  testing per the source repo's `REAL_DEVICE_TESTING.md`).

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

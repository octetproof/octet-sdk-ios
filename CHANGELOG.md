# Changelog

All notable changes to the OctetSDK for iOS are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

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

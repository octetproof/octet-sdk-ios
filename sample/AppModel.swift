import Foundation
import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine
import OctetSDK

// MARK: - Pipeline model

enum StepState { case pending, active, done }

struct PipelineStep: Identifiable {
    let id: String
    let label: String
    var state: StepState = .pending
    var seconds: Double?
    var activeAt: Date?

    var kind: StatusKind {
        switch state {
        case .pending: return .pending
        case .active: return .active
        case .done: return .ok
        }
    }
}

/// One line of the curated, sanitized debug feed. Content comes ONLY from public
/// verdict fields + the sample's own timings — never a coordinate/key/token/id.
struct DebugLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}

/// The Generate result-card payload (the predicate answer, not a verification).
struct GenerateResult {
    let result: OctetVerdict.Result
    let regionLabel: String
    let bucket: ConfidenceBucket
    let score: Double
    let fresh: Bool
    let stored: StoredProof?
    var battery: BatteryCost?
}

/// Battery consumed across one proof run. iOS exposes only a coarse charge level
/// (~1% steps) and no current/mAh sensor, so `pct` is usually nil (below that
/// resolution) and consumption is only meaningful off-charger — the Android
/// build reads a hardware charge counter for real mAh instead.
struct BatteryCost {
    let pct: Int?
    let charging: Bool
    let durationSec: Double
}

// MARK: - App model

@MainActor
final class AppModel: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum SDKState: Equatable {
        case idle, starting, ready, failed(String)
        var label: String {
            switch self {
            case .idle: return "Waiting for permission…"
            case .starting: return "SDK initializing…"
            case .ready: return "SDK ready"
            case .failed(let m): return "SDK failed: \(m)"
            }
        }
    }

    @Published var sdkState: SDKState = .idle
    @Published var licenseLine: String = ""
    @Published var licenseNotice: String?
    @Published var selectedCountry: Country = defaultCountry
    @Published var steps: [PipelineStep] = []
    @Published var isGenerating = false
    /// When on, Generate bypasses the freshness cache and mints a brand-new proof
    /// (SDK `isWithin(forceFresh: true)`) instead of possibly reusing a still-valid
    /// cached fix — handy to prove a *fresh* run really happened. Bound to the UI toggle.
    @Published var forceFresh = false
    @Published var lastResult: GenerateResult?
    @Published var debug: [DebugLine] = []
    /// The SDK's own public log stream (lifecycle / verdicts / errors), captured
    /// live when "Verbose SDK logs" is enabled in the hidden Dev menu. `PublicLog`
    /// is the SDK's PII-disciplined public surface — never internal signals /
    /// weights / scores, never coordinates / keys / identifiers — so surfacing it
    /// here is leak-safe. Only wired in DEBUG (the toggle is compiled out of release).
    @Published var sdkLog: [DebugLine] = []
    /// Set when a `.octetproof` arrives (share/AirDrop/import) → drives the preview sheet.
    @Published var pendingImport: ProofEnvelope?

    @Published var userLocation: CLLocationCoordinate2D?
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.5, longitude: 14.5),
                           span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)))

    let store: ProofStore
    let settings: AppSettings

    private var sdk: OctetSdk?
    private let locationManager = CLLocationManager()
    private var startTask: Task<Void, Never>?

    private lazy var sdkLogSink = SampleLogSink { [weak self] line in self?.appendSDKLog(line) }
    private var sdkLogInstalled = false

    // Region-picker defaulting: seed the picker from the device's GPS country on
    // the first fix, unless the user has already chosen one.
    private var didAutoSelectCountry = false
    private var userOverrodeCountry = false

    init(store: ProofStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        steps = baseSteps()
        applyVerboseLogging()   // honour a persisted "verbose SDK logs" setting at launch
    }

    var isReady: Bool { if case .ready = sdkState { return true } else { return false } }

    // MARK: - lifecycle

    func bootstrap() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            handleAuthorization(status)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.handleAuthorization(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor in
            let first = (self.userLocation == nil)
            self.userLocation = coord
            if first {
                self.cameraPosition = .region(MKCoordinateRegion(
                    center: coord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                self.autoSelectCountry(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            }
        }
    }

    // MARK: - region selection

    /// The user explicitly picked a region — record it so the GPS default won't
    /// override their choice.
    func userSelectedCountry(_ c: Country) {
        selectedCountry = c
        userOverrodeCountry = true
    }

    /// One-time: default the region picker to the device's actual GPS country
    /// (reverse-geocoded) on the first fix, unless the user already chose one.
    private func autoSelectCountry(from location: CLLocation) {
        guard !didAutoSelectCountry, !userOverrodeCountry else { return }
        didAutoSelectCountry = true
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard self != nil,
                  let iso = placemarks?.first?.isoCountryCode,
                  let match = demoCountries.first(where: { $0.id == iso }) else { return }
            Task { @MainActor in
                guard let self, !self.userOverrodeCountry else { return }
                self.selectedCountry = match
            }
        }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        locationManager.startUpdatingLocation()
        guard startTask == nil, sdk == nil else { return }
        sdkState = .starting
        markActive("init")
        log("sdk.start requested")
        startTask = Task { @MainActor in
            let t0 = Date()
            do {
                // NOTE: the committed sample is prod-only. A dev sandbox token + the
                // DEBUG proof-export are your LOCAL overlay (see the #54 recovery note);
                // they are intentionally NOT wired here so the public sample stays clean.
                let config = OctetConfig(
                    licenseKey: LocalConfig.licenseKey,
                    proofUploadUrl: settings.uploadsEnabled ? LocalConfig.activationServerUrl : nil,
                    advanced: AdvancedConfig(
                        activationServerUrl: LocalConfig.activationServerUrl,
                        logLevel: settings.verboseLogs ? .verbose : .info))
                let started = try await Octet.start(config: config, startPosition: nil)
                self.sdk = started
                #if DEBUG
                // octet-verify-private#54: emit the semantic-binding-v2 stage so the
                // verifier can be exercised against a real device proof. DEBUG-only —
                // compiled out of release; toggled from the hidden dev menu.
                if settings.semanticV2 { OctetSemanticV2Debug.setEnabled(true) }
                #endif
                complete("init", since: t0)
                self.sdkState = .ready
                log("sdk.start ok")
                log("activation ✓")
                if let s = started.licenseStatus {
                    licenseLine = "license \(s.state.rawValue)"
                    if s.state == .gracePeriod, let days = s.daysUntilHardStop {
                        licenseNotice = "Your license expires in \(days) day\(days == 1 ? "" : "s") — please renew."
                    }
                }
            } catch {
                self.sdkState = .failed("\(error)")
                markFailed("init")
                log("sdk.start failed")
            }
        }
    }

    // MARK: - generate

    func generate() async {
        guard let sdk = sdk, !isGenerating else { return }
        isGenerating = true
        lastResult = nil
        resetForGenerate()
        log(forceFresh ? "generate: region \(selectedCountry.id) (force-fresh)" : "generate: region \(selectedCountry.id)")

        UIDevice.current.isBatteryMonitoringEnabled = true
        let battStart = UIDevice.current.batteryLevel
        let chargingStart = Self.isCharging(UIDevice.current.batteryState)
        let t0 = Date()

        let animator = Task { await animateSteps() }
        let verdict = await sdk.loc.isWithin(region: .country(isoCode: selectedCountry.id),
                                             atTime: Date(), forceFresh: forceFresh)
        // Let the pipeline animation finish its minimum run so a fast (cached) proof
        // is still a visibly NEW run, not a silent flash of the old checkmarks.
        _ = await animator.value
        finishSteps()

        let battery = Self.batteryCost(startLevel: battStart, chargingStart: chargingStart, since: t0)

        // forceFresh always mints a new proof, so a produced proof is fresh;
        // otherwise trust the SDK's honest "freshly generated" message.
        let fresh = forceFresh || verdict.message.localizedCaseInsensitiveContains("fresh")
        log("fix quality: \(bucketLabel(verdict.confidence.overallScore))")

        var stored: StoredProof?
        if let proof = verdict.proof {
            let sp = makeStoredProof(from: proof, result: verdict.result)
            let isNew = store.add(sp)
            stored = sp
            log(isNew ? "proof built (\(proof.proofBytes.count) B) · stored" : "proof already stored")
            if settings.uploadsEnabled { log("upload queued") }
        } else {
            log("no proof produced (\(reasonLabel(verdict.reason)))")
        }

        lastResult = GenerateResult(
            result: verdict.result,
            regionLabel: selectedCountry.name,
            bucket: ConfidenceBucket(score: verdict.confidence.overallScore),
            score: verdict.confidence.overallScore,
            fresh: fresh,
            stored: stored,
            battery: battery)
        isGenerating = false
    }

    // MARK: - battery cost (coarse; iOS has no charge-counter/current API)

    private static func isCharging(_ s: UIDevice.BatteryState) -> Bool {
        s == .charging || s == .full
    }

    private static func batteryCost(startLevel: Float, chargingStart: Bool, since t0: Date) -> BatteryCost {
        let endLevel = UIDevice.current.batteryLevel
        let charging = chargingStart || isCharging(UIDevice.current.batteryState)
        let duration = Date().timeIntervalSince(t0)
        // Level is -1 when unknown; iOS rounds to ~1% (often 5%) steps, so a
        // single proof usually shows no measurable drop — reported honestly.
        let pct: Int?
        if !charging, startLevel >= 0, endLevel >= 0 {
            let drop = Int(((startLevel - endLevel) * 100).rounded())
            pct = drop > 0 ? drop : nil
        } else {
            pct = nil
        }
        return BatteryCost(pct: pct, charging: charging, durationSec: duration)
    }

    private func makeStoredProof(from proof: LocationProof, result: OctetVerdict.Result) -> StoredProof {
        StoredProof(
            id: UUID().uuidString,
            proofB64: proof.proofBytes.base64EncodedString(),
            regionISO: selectedCountry.id,
            regionLabel: selectedCountry.name,
            level: levelLabel(proof.level),
            generatedAtMs: proof.timestampMs,
            createdAt: Date(),
            confidenceScore: proof.confidence.overallScore,
            predicateResult: resultLabel(result),
            imported: false,
            sizeBytes: proof.proofBytes.count)
    }

    // MARK: - verify

    /// Verify a stored proof. `expectedISO` (an ISO alpha-2 country the caller
    /// picks) drives the region-claim / region-type / region-contains checks: when
    /// set, the verifier confirms the proof's *claimed* location against that
    /// country; when nil those three are reported NOT-CHECKED. This is deliberately
    /// NOT the `isWithin` query region — the query is a question, while the proof
    /// claims the device's actual location, which differs when the answer was "no".
    func verify(_ proof: StoredProof, expectedISO: String?) -> ProofVerification {
        var options = VerifyOptions()
        if let iso = expectedISO, iso.count == 2 {
            options.expectedRegion = .country(isoCode: iso)
        }
        return Octet.verify(proofBytes: proof.proofBytes, options: options)
    }

    // MARK: - import

    /// Verify + store an incoming `.octetproof` envelope. Returns the stored proof
    /// and whether it was newly added (false = already had it).
    func importEnvelope(_ env: ProofEnvelope) -> (proof: StoredProof, isNew: Bool) {
        let bytes = Data(base64Encoded: env.proofB64) ?? Data()
        let label = env.region.count == 2 ? countryName(for: env.region) : env.region
        let sp = StoredProof(
            id: UUID().uuidString,
            proofB64: env.proofB64,
            regionISO: env.region.count == 2 ? env.region : nil,
            regionLabel: label,
            level: "—",
            generatedAtMs: env.generatedAtMs,
            createdAt: Date(),
            confidenceScore: 0,
            predicateResult: nil,
            imported: true,
            sizeBytes: bytes.count)
        let isNew = store.add(sp)
        return (sp, isNew)
    }

    // MARK: - pipeline helpers

    private func baseSteps() -> [PipelineStep] {
        [PipelineStep(id: "init", label: "SDK initialized"),
         PipelineStep(id: "warmup", label: "Sensors warmed up"),
         PipelineStep(id: "locate", label: "Location fixed"),
         PipelineStep(id: "generate", label: "Proof generated")]
    }

    private func resetForGenerate() {
        // Keep init done; reset the rest; append the upload step when uploads are on.
        var s = steps.filter { $0.id == "init" }
        if s.isEmpty { s = [PipelineStep(id: "init", label: "SDK initialized", state: .done)] }
        s += [PipelineStep(id: "warmup", label: "Sensors warmed up"),
              PipelineStep(id: "locate", label: "Location fixed"),
              PipelineStep(id: "generate", label: "Proof generated")]
        if settings.uploadsEnabled { s.append(PipelineStep(id: "upload", label: "Upload queued")) }
        steps = s
    }

    private func animateSteps() async {
        markActive("warmup")
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }
        complete("warmup"); markActive("locate")
        try? await Task.sleep(for: .milliseconds(700))
        if Task.isCancelled { return }
        complete("locate"); markActive("generate")
    }

    /// Called when the real query returns — complete whatever is still running.
    private func finishSteps() {
        for id in ["warmup", "locate", "generate", "upload"] {
            if let i = steps.firstIndex(where: { $0.id == id }), steps[i].state != .done {
                if steps[i].state == .pending { steps[i].activeAt = Date() }
                complete(id)
            }
        }
    }

    private func markActive(_ id: String) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[i].state = .active
        steps[i].activeAt = Date()
    }

    private func complete(_ id: String, since: Date? = nil) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        let from = since ?? steps[i].activeAt ?? Date()
        steps[i].seconds = max(0, Date().timeIntervalSince(from))
        steps[i].state = .done
    }

    private func markFailed(_ id: String) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[i].state = .pending
    }

    // MARK: - curated debug log (sanitized)

    func log(_ text: String) {
        debug.append(DebugLine(time: Date(), text: text))
        if debug.count > 200 { debug.removeFirst(debug.count - 200) }
    }

    func clearDebug() { debug.removeAll() }

    // MARK: - verbose SDK log stream (PublicLog surface; debug-only)

    /// Install or remove the sample's `PublicLog` sink to match the "Verbose SDK
    /// logs" toggle. Live — no restart needed to start/stop capturing. `PublicLog`
    /// carries only the SDK's public lifecycle / verdict / error events, so this
    /// never surfaces internal signals, scores, coordinates, keys, or identifiers.
    func applyVerboseLogging() {
        if settings.verboseLogs {
            if !sdkLogInstalled { PublicLog.shared.addSink(sdkLogSink); sdkLogInstalled = true }
        } else {
            if sdkLogInstalled { PublicLog.shared.removeSink(sdkLogSink); sdkLogInstalled = false }
            sdkLog.removeAll()
        }
    }

    /// Called from the (possibly background) `LogSink` — hop to the main actor to
    /// mutate the published buffer. Capped so a long session can't grow unbounded.
    nonisolated func appendSDKLog(_ text: String) {
        Task { @MainActor in
            self.sdkLog.append(DebugLine(time: Date(), text: text))
            if self.sdkLog.count > 300 { self.sdkLog.removeFirst(self.sdkLog.count - 300) }
        }
    }

    func clearSDKLog() { sdkLog.removeAll() }

    // MARK: - labels (public, non-sensitive)

    func bucketLabel(_ score: Double) -> String {
        switch ConfidenceBucket(score: score) {
        case .high: return "strong"
        case .medium: return "ok"
        case .low: return "weak"
        }
    }

    func resultLabel(_ r: OctetVerdict.Result) -> String {
        switch r { case .yes: return "inside"; case .no: return "outside"; case .indeterminate: return "indeterminate" }
    }

    func reasonLabel(_ r: OctetVerdict.ReasonCode) -> String {
        "\(r)"
    }

    func levelLabel(_ l: ProofLevel) -> String {
        switch l {
        case .onEarth: return "ON_EARTH"
        case .country: return "COUNTRY"
        case .subdivision: return "SUBDIVISION"
        case .city: return "CITY"
        default: return "—"
        }
    }
}

/// A `LogSink` that forwards the SDK's public log lines to a callback (→ the
/// in-app SDK-log view). Only `PublicLog` events reach here — the SDK keeps its
/// internal signals / scores on `InternalLog`, which is never exposed.
final class SampleLogSink: LogSink, @unchecked Sendable {
    private let onLine: (String) -> Void
    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func log(level: LogLevel, tag: String, message: String, error: Error?) {
        let mark: String
        switch level {
        case .verbose: mark = "V"
        case .debug: mark = "D"
        case .info: mark = "I"
        case .warn: mark = "W"
        case .error: mark = "E"
        }
        var line = "[\(mark)] \(tag): \(message)"
        if let error { line += " — \(error)" }
        onLine(line)
    }
}

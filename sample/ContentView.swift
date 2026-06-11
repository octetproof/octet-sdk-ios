import SwiftUI
import CoreLocation
import MapKit
import OctetSDK

// License key comes from `LocalConfig.swift` (gitignored). If that
// file isn't there, the build fails with `cannot find 'LocalConfig'
// in scope`; copy `LocalConfig.swift.example` and paste your key.

// MARK: - Country list

/// Display row in the country picker. `id` is the ISO 3166-1 alpha-2
/// code — the same shape `OctetRegion.country(isoCode:)` accepts.
struct Country: Identifiable, Hashable {
    let id: String   // ISO alpha-2
    let name: String
}

/// ISO 3166-1 codes representing dependent territories, overseas
/// departments, or otherwise non-sovereign entities. Best effort —
/// diplomatically-contested edges (Taiwan / Palestine / Cook Islands /
/// Niue) are KEPT in the picker rather than asserted as non-sovereign
/// here.
private let dependentTerritoryCodes: Set<String> = [
    "AQ", "AX", "BV", "CC", "CX", "EH", "FK", "FO", "GF", "GG",
    "GI", "GL", "GP", "GS", "GU", "HK", "HM", "IM", "IO", "JE",
    "KY", "MF", "MO", "MP", "MQ", "MS", "NC", "NF", "PF", "PM",
    "PN", "PR", "RE", "SH", "SJ", "TC", "TF", "TK", "UM", "VG",
    "VI", "WF", "YT",
]

/// Full ISO 3166-1 alpha-2 list minus dependent territories, localized
/// to the device's current locale and sorted by display name using
/// locale-aware collation. Pulled from `Locale.Region.isoRegions` at
/// startup so we don't carry a hardcoded country table that decays.
let demoCountries: [Country] = {
    let locale = Locale.current
    return Locale.Region.isoRegions
        .map { $0.identifier }
        .filter { iso in
            iso.count == 2 && !dependentTerritoryCodes.contains(iso)
        }
        .compactMap { iso -> Country? in
            guard let name = locale.localizedString(forRegionCode: iso) else { return nil }
            return Country(id: iso, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}()

/// Default selection — device's current region code, or the first
/// entry in the sorted list as a fallback (which under most locales
/// is something defensible like "Afghanistan" / "Andorra").
private let defaultCountry: Country = {
    let deviceCode = Locale.current.region?.identifier ?? ""
    return demoCountries.first(where: { $0.id == deviceCode })
        ?? demoCountries.first(where: { $0.id == "US" })
        ?? demoCountries[0]
}()

// MARK: - User-location annotation (Map needs an Identifiable item)

/// `fileprivate` (not `private`) so `ToyViewModel.userPin` can use it
/// as its declared type without Swift complaining about access-level
/// mismatch.
fileprivate struct UserPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - View model

@MainActor
final class ToyViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase: String {
        case waitingForPermission = "Waiting for permission…"
        case starting = "SDK starting…"
        case ready = "SDK ready — waiting for first proof…"
        case failed = "SDK failed to start"
    }

    @Published var phase: Phase = .waitingForPermission
    @Published var sdk: OctetSdk?
    @Published var lastVerdict: String = ""
    @Published var licenseExpiryNotice: String?

    /// Country the user selected from the picker. Drives the
    /// `isWithin` test.
    @Published var selectedCountry: Country = defaultCountry

    /// Latest device-location fix. Used to display a pin. Nil until
    /// the OS hands the first update.
    @Published var userLocation: CLLocationCoordinate2D?

    /// Camera state for SwiftUI's iOS-17 `Map(position:)` API. Default
    /// to a world-ish center until the first GPS fix lands.
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.5, longitude: 14.5),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
        )
    )

    private let locationManager = CLLocationManager()
    private var startTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

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

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor in
            let isFirstFix = (self.userLocation == nil)
            self.userLocation = coord
            // Zoom in tight on the first fix only; subsequent fixes
            // just slide the pin so the user's manual pan isn't fought.
            if isFirstFix {
                self.cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
        }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        locationManager.startUpdatingLocation()
        guard startTask == nil, sdk == nil else { return }
        phase = .starting
        startTask = Task { @MainActor in
            do {
                let config = OctetConfig(
                    licenseKey: LocalConfig.licenseKey,
                    // #122/#123: opt-in proof upload to prod backend.
                    // Same host as activation since octet-proofs is
                    // co-hosted with the license server.
                    proofUploadUrl: LocalConfig.activationServerUrl,
                    advanced: AdvancedConfig(
                        activationServerUrl: LocalConfig.activationServerUrl))
                let started = try await Octet.start(config: config, startPosition: nil)
                self.sdk = started
                self.phase = .ready
                if let status = started.licenseStatus {
                    self.lastVerdict = "license: \(status.state.rawValue), " +
                        "\(status.daysUntilHardStop ?? -1)d remaining"
                    if status.state == .gracePeriod, let days = status.daysUntilHardStop {
                        self.licenseExpiryNotice =
                            "Your license expires in \(days) day\(days == 1 ? "" : "s") — please renew."
                    }
                }
            } catch {
                self.phase = .failed
                self.lastVerdict = "start error: \(error)"
            }
        }
    }

    func runIsWithinSelected() async {
        guard let sdk = sdk else { return }
        let iso = selectedCountry.id
        let verdict = await sdk.loc.isWithin(region: .country(isoCode: iso), atTime: Date())
        lastVerdict = """
        country: \(iso) (\(selectedCountry.name))
        result:  \(verdict.result)
        reason:  \(verdict.reason)
        message: \(verdict.message)
        proof:   \(verdict.proof != nil ? "set" : "nil")
        """
    }

    fileprivate var userPin: UserPin? {
        userLocation.map { UserPin(coordinate: $0) }
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var vm = ToyViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Octet v1 Toy").font(.title2).bold()
            Text(vm.phase.rawValue).foregroundStyle(.secondary)

            if let notice = vm.licenseExpiryNotice {
                Text(notice)
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.3))
                    .cornerRadius(8)
            }

            // Map — centered on the device's last GPS fix once available.
            // Uses Apple's MapKit (free, no API key needed on Apple
            // platforms). iOS-17 Map API with MapCameraPosition binding.
            Map(position: $vm.cameraPosition) {
                if let pin = vm.userPin {
                    Marker("You", coordinate: pin.coordinate)
                        .tint(.red)
                }
            }
            .frame(height: 220)
            .cornerRadius(12)

            HStack {
                Text("Country:")
                Picker("Country", selection: $vm.selectedCountry) {
                    ForEach(demoCountries) { c in
                        Text("\(c.name) (\(c.id))").tag(c)
                    }
                }
                .pickerStyle(.menu)
            }

            Button("Test: isWithin(\(vm.selectedCountry.id))") {
                Task { await vm.runIsWithinSelected() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.sdk == nil)

            if !vm.lastVerdict.isEmpty {
                Text(vm.lastVerdict)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding()
        .task { vm.bootstrap() }
    }
}

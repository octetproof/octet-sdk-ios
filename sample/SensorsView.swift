import SwiftUI

/// Diagnostics **Sensors** screen, reached from the hidden Developer menu. A
/// live readout of the device's own sensors via public frameworks only —
/// nothing from the Octet SDK (no signal weights, scores, keys, or identifiers).
///
/// Honest about iOS platform limits (owner-approved): GPS satellite data,
/// cell-tower lists, and Wi-Fi scans aren't exposed by iOS, so those rows say so
/// rather than fabricating values — that full picture is the Android build's job.
struct SensorsView: View {
    @StateObject private var m = SensorMonitor()

    var body: some View {
        List {
            locationSection
            motionSection
            cellularSection
            wifiSection
            batterySection
        }
        .navigationTitle("Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    // MARK: - Location & GNSS quality

    private var locationSection: some View {
        Section {
            kv("Authorization", m.authStatus, info: "Authorization")
            kv("Source", m.locationSource, info: "Source")
            kv("Latitude", m.coordinate.map { String(format: "%.6f°", $0.latitude) } ?? "—", info: "Coordinates")
            kv("Longitude", m.coordinate.map { String(format: "%.6f°", $0.longitude) } ?? "—")
            kv("Horizontal acc.", fmt(m.horizontalAccuracy, "m"), info: "Horizontal accuracy")
            kv("Vertical acc.", fmt(m.verticalAccuracy, "m"), info: "Vertical accuracy")
            kv("Altitude", fmt(m.altitude, "m"), info: "Altitude")
            kv("Speed", fmt(m.speed, "m/s"), info: "Speed")
            kv("Course", m.course.map { String(format: "%.0f°", $0) } ?? "—", info: "Course")
            NavigationLink { SensorMapView() } label: {
                Label("Show on map", systemImage: "map")
            }
        } header: {
            Label("Location & GNSS quality", systemImage: "location.fill")
        } footer: {
            Text("GPS satellite count, SNR, and sky position aren't exposed by iOS public APIs — the Android build shows them.")
        }
    }

    // MARK: - Motion & inertial

    private var motionSection: some View {
        Section {
            sensorRow("Accelerometer", available: m.accelAvailable, active: m.accel != nil,
                      live: m.accel.map { String(format: "x %.2f  y %.2f  z %.2f g", $0.x, $0.y, $0.z) })
            sensorRow("Gyroscope", available: m.gyroAvailable, active: m.rotation != nil,
                      live: m.rotation.map { String(format: "%.2f  %.2f  %.2f rad/s", $0.x, $0.y, $0.z) })
            sensorRow("Magnetometer", available: m.magAvailable, active: m.magnetic != nil,
                      live: m.magnetic.map { String(format: "%.0f / %.0f / %.0f µT", $0.x, $0.y, $0.z) })
            sensorRow("Barometer", available: m.barometerAvailable, active: m.pressureKPa != nil,
                      live: m.pressureKPa.map { String(format: "%.2f kPa", $0) })
            if m.deviceMotionAvailable {
                kv("Attitude", m.attitude.map {
                    String(format: "roll %.0f°  pitch %.0f°  yaw %.0f°", deg($0.roll), deg($0.pitch), deg($0.yaw))
                } ?? "—", info: "Attitude")
                kv("Rel. altitude", fmt(m.relativeAltitude, "m"))
                kv("Mag. calibration", m.magCalibration)
            }
        } header: {
            Label("Motion & inertial", systemImage: "gyroscope")
        } footer: {
            Text("● active   ○ available, idle   ✕ unavailable on this device.")
        }
    }

    // MARK: - Cellular & radio

    private var cellularSection: some View {
        Section {
            kv("Radio access", m.radioTech, info: "Radio access")
            kv("Carrier", "unavailable")
            kv("Cell towers", "unavailable", info: "Cell towers")
        } header: {
            Label("Cellular & radio", systemImage: "antenna.radiowaves.left.and.right")
        } footer: {
            Text("Carrier name and MCC/MNC were removed from iOS public APIs in iOS 16; cell IDs, signal, and neighbouring towers aren't exposed either. The Android build shows towers and signal.")
        }
    }

    // MARK: - Wi-Fi

    private var wifiSection: some View {
        Section {
            kv("Nearby networks", "unavailable", info: "Nearby networks")
        } header: {
            Label("Wi-Fi", systemImage: "wifi")
        } footer: {
            Text("iOS doesn't permit scanning nearby Wi-Fi networks (it needs an Apple-granted hotspot entitlement). Wi-Fi positioning lands on the Android build.")
        }
    }

    // MARK: - Battery

    private var batterySection: some View {
        Section {
            kv("Level", m.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", info: "Battery level")
            kv("State", batteryStateLabel(m.batteryState), info: "Battery state")
        } header: {
            Label("Battery", systemImage: "battery.100")
        } footer: {
            Text("iOS exposes only the charge level in coarse steps and no current/mAh sensor — so per-proof consumption can't be measured precisely, and only off-charger. (The Android build reads the hardware charge counter for real mAh.)")
        }
    }

    private func batteryStateLabel(_ s: UIDevice.BatteryState) -> String {
        switch s {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "on battery"
        case .unknown: return "—"
        @unknown default: return "—"
        }
    }

    // MARK: - row helpers

    private func kv(_ k: String, _ v: String, info: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(k).foregroundStyle(.secondary)
            if let info { InfoButton(key: info) }
            Spacer()
            Text(v).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func sensorRow(_ name: String, available: Bool, active: Bool, live: String?) -> some View {
        HStack(spacing: Theme.Space.s) {
            StatusDot(kind: !available ? .bad : (active ? .ok : .pending))
            Text(name).foregroundStyle(.secondary)
            InfoButton(key: name)
            Spacer()
            Text(!available ? "unavailable" : (live ?? "starting…"))
                .font(Theme.mono(12))
                .foregroundStyle(available ? .primary : Theme.neutral)
        }
        .font(.subheadline)
    }

    private func fmt(_ d: Double?, _ unit: String) -> String {
        d.map { String(format: "%.1f %@", $0, unit) } ?? "—"
    }

    private func deg(_ rad: Double) -> Double { rad * 180 / .pi }
}

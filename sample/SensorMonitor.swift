import Foundation
import CoreMotion
import CoreLocation
import CoreTelephony
import UIKit

/// Live device-sensor readout for the diagnostics **Sensors** screen. Gathers
/// ONLY public-framework data — CoreMotion (inertial), CoreLocation (GNSS
/// quality), CoreTelephony (radio) — never anything from the Octet SDK: no
/// signal weights, no scores, no keys/tokens/identifiers. Starts on appear and
/// stops on disappear, so nothing runs in the background.
///
/// Deliberate iOS-platform honesty (see the view): raw GNSS satellite data,
/// cell-tower lists, and Wi-Fi scans are NOT exposed by iOS public APIs, so this
/// monitor doesn't fabricate them — those rows are marked unavailable in the UI
/// and are where the Android build does the real job.
final class SensorMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: Location & GNSS quality
    @Published var authStatus = "—"
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var horizontalAccuracy: Double?
    @Published var verticalAccuracy: Double?
    @Published var altitude: Double?
    @Published var speed: Double?
    @Published var course: Double?
    /// Real vs simulated fix (iOS 15+ `CLLocation.sourceInformation`).
    @Published var locationSource = "—"

    // MARK: Motion & inertial (live)
    @Published var accel: CMAcceleration?
    @Published var rotation: CMRotationRate?
    @Published var magnetic: CMMagneticField?
    @Published var attitude: Attitude?
    @Published var magCalibration = "—"
    @Published var pressureKPa: Double?
    @Published var relativeAltitude: Double?

    // MARK: Cellular & radio
    @Published var radioTech = "—"

    // MARK: Battery (UIDevice — coarse level + charge state only; no current/mAh API)
    @Published var batteryLevel: Float?
    @Published var batteryState: UIDevice.BatteryState = .unknown

    struct Attitude { let roll, pitch, yaw: Double }

    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let location = CLLocationManager()
    private let telephony = CTTelephonyNetworkInfo()
    private var batteryObservers: [NSObjectProtocol] = []

    // Static availability (synchronously knowable).
    var accelAvailable: Bool { motion.isAccelerometerAvailable }
    var gyroAvailable: Bool { motion.isGyroAvailable }
    var magAvailable: Bool { motion.isMagnetometerAvailable }
    var deviceMotionAvailable: Bool { motion.isDeviceMotionAvailable }
    var barometerAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func start() {
        // Location — best accuracy so the quality readout is meaningful.
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        authStatus = Self.authString(location.authorizationStatus)
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
        location.startUpdatingLocation()

        // Inertial — raw streams at 10 Hz, delivered on the main queue so the
        // @Published mutations are SwiftUI-safe.
        let hz = 0.1
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = hz
            motion.startAccelerometerUpdates(to: .main) { [weak self] d, _ in
                self?.accel = d?.acceleration
            }
        }
        if motion.isGyroAvailable {
            motion.gyroUpdateInterval = hz
            motion.startGyroUpdates(to: .main) { [weak self] d, _ in
                self?.rotation = d?.rotationRate
            }
        }
        if motion.isMagnetometerAvailable {
            motion.magnetometerUpdateInterval = hz
            motion.startMagnetometerUpdates(to: .main) { [weak self] d, _ in
                self?.magnetic = d?.magneticField
            }
        }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = hz
            motion.startDeviceMotionUpdates(to: .main) { [weak self] d, _ in
                guard let d else { return }
                self?.attitude = Attitude(roll: d.attitude.roll,
                                          pitch: d.attitude.pitch,
                                          yaw: d.attitude.yaw)
                self?.magCalibration = Self.calString(d.magneticField.accuracy)
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] d, _ in
                self?.relativeAltitude = d?.relativeAltitude.doubleValue
                self?.pressureKPa = d?.pressure.doubleValue
            }
        }

        refreshCellular()

        // Battery — coarse level + charge state (iOS exposes no current/mAh API).
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        batteryObservers = [
            NotificationCenter.default.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refreshBattery() },
            NotificationCenter.default.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refreshBattery() },
        ]
    }

    func stop() {
        location.stopUpdatingLocation()
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        motion.stopMagnetometerUpdates()
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        batteryObservers.forEach { NotificationCenter.default.removeObserver($0) }
        batteryObservers.removeAll()
    }

    func refreshBattery() {
        let d = UIDevice.current
        let lvl = d.batteryLevel          // -1 when unknown / monitoring off
        batteryLevel = lvl >= 0 ? lvl : nil
        batteryState = d.batteryState
    }

    /// Serving radio-access technology is still exposed on modern iOS. Cell IDs,
    /// signal strength, and neighbouring towers are NOT — see the view's note.
    private func refreshCellular() {
        if let raw = telephony.serviceCurrentRadioAccessTechnology?.values.first {
            radioTech = Self.radioName(raw)
        } else {
            radioTech = "—"
        }
    }

    // MARK: - CLLocationManagerDelegate (main-thread callbacks)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = Self.authString(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coordinate = loc.coordinate
        horizontalAccuracy = loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil
        verticalAccuracy = loc.verticalAccuracy >= 0 ? loc.verticalAccuracy : nil
        altitude = loc.altitude
        speed = loc.speed >= 0 ? loc.speed : nil
        course = loc.course >= 0 ? loc.course : nil
        if let src = loc.sourceInformation {
            locationSource = src.isSimulatedBySoftware ? "Simulated (software)"
                : src.isProducedByAccessory ? "External accessory"
                : "Device sensor"
        } else {
            locationSource = "Device sensor"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort screen — a transient location error just leaves the last
        // reading in place; no need to surface it.
    }

    // MARK: - formatting helpers

    static func authString(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While-Using"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "—"
        }
    }

    static func calString(_ a: CMMagneticFieldCalibrationAccuracy) -> String {
        switch a {
        case .uncalibrated: return "Uncalibrated"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        @unknown default: return "—"
        }
    }

    static func radioName(_ raw: String) -> String {
        switch raw {
        case CTRadioAccessTechnologyNR: return "5G (NR)"
        case CTRadioAccessTechnologyNRNSA: return "5G (NSA)"
        case CTRadioAccessTechnologyLTE: return "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA, CTRadioAccessTechnologyeHRPD,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB: return "3G"
        case CTRadioAccessTechnologyCDMA1x, CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyEdge: return "2G"
        default: return "—"
        }
    }
}

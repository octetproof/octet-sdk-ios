import Foundation
import UIKit
import CryptoKit
import CoreMotion
import CoreLocation
import DeviceCheck

/// Non-sensitive device capability readout for the Device Info screen.
/// Deliberately capabilities + states ONLY — never a device identifier
/// (UDID / IDFV / serial), never a key or a permission secret.
struct InfoRow: Identifiable { let id = UUID(); let key: String; let value: String }
struct InfoCategory: Identifiable { let id = UUID(); let title: String; let icon: String; let rows: [InfoRow] }

enum DeviceInfo {
    /// The synchronously-knowable categories (OS, secure hardware, sensors,
    /// permissions). SDK/License + Network are composed in the view.
    static func categories() -> [InfoCategory] {
        [operatingSystem(), secureHardware(), sensors(), permissions()]
    }

    private static func operatingSystem() -> InfoCategory {
        InfoCategory(title: "Operating system", icon: "iphone", rows: [
            InfoRow(key: "system", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            InfoRow(key: "model", value: modelIdentifier()),   // model class, not a unique id
        ])
    }

    private static func secureHardware() -> InfoCategory {
        let se = SecureEnclave.isAvailable
        let appAttest = DCAppAttestService.shared.isSupported
        return InfoCategory(title: "Secure hardware", icon: "lock.shield", rows: [
            InfoRow(key: "Secure Enclave", value: se ? "yes" : "no"),
            InfoRow(key: "App Attest", value: appAttest ? "supported" : "unsupported"),
            InfoRow(key: "key backing", value: se ? "hardware" : "software"),
        ])
    }

    private static func sensors() -> InfoCategory {
        let m = CMMotionManager()
        func yn(_ b: Bool) -> String { b ? "available" : "unavailable" }
        return InfoCategory(title: "Sensors", icon: "dot.radiowaves.left.and.right", rows: [
            InfoRow(key: "Location", value: yn(CLLocationManager.locationServicesEnabled())),
            InfoRow(key: "Accelerometer", value: yn(m.isAccelerometerAvailable)),
            InfoRow(key: "Gyroscope", value: yn(m.isGyroAvailable)),
            InfoRow(key: "Magnetometer", value: yn(m.isMagnetometerAvailable)),
            InfoRow(key: "Barometer", value: yn(CMAltimeter.isRelativeAltitudeAvailable())),
        ])
    }

    private static func permissions() -> InfoCategory {
        InfoCategory(title: "Permissions", icon: "hand.raised", rows: [
            InfoRow(key: "Location", value: locationAuth()),
            InfoRow(key: "Motion", value: motionAuth()),
        ])
    }

    // MARK: - helpers

    static func modelIdentifier() -> String {
        var sys = utsname(); uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
        return id.isEmpty ? "—" : id
    }

    private static func locationAuth() -> String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While-Using"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "—"
        }
    }

    private static func motionAuth() -> String {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "—"
        }
    }
}

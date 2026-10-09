import SwiftUI

/// Plain-language, one-line explanations of each signal on the Sensors screen.
/// Deliberately non-technical and leak-free: they describe what the *public OS
/// reading* means, never anything about the SDK's internal scoring or weights.
/// Mirrors the Android build's `signalGlossary`.
let signalGlossary: [String: String] = [
    "Source": "Where this location came from — the device's own GPS/sensors, or (a red flag) a simulated/accessory source.",
    "Authorization": "The location permission you granted this app: while-using, always, or denied.",
    "Coordinates": "The device's current latitude and longitude — its position on Earth.",
    "Horizontal accuracy": "The estimated radius of error around the position — smaller is better (e.g. 5 m is a strong fix).",
    "Vertical accuracy": "The estimated error on altitude — how uncertain the height reading is.",
    "Altitude": "Height above mean sea level, estimated from GPS and the barometer.",
    "Speed": "How fast the device is moving over the ground.",
    "Course": "The compass direction the device is travelling in (0° = North).",
    "Accelerometer": "Measures acceleration on three axes — how the device is being moved or tilted, plus gravity.",
    "Gyroscope": "Measures rotation rate on three axes — how fast the device is turning.",
    "Magnetometer": "Measures the magnetic field on three axes — the basis of the compass.",
    "Barometer": "Measures air pressure, which helps estimate altitude and floor level.",
    "Attitude": "The device's orientation — roll, pitch, and yaw — fused from the motion sensors.",
    "Radio access": "The current mobile network technology in use (5G, LTE, 3G…).",
    "Cell towers": "iOS doesn't expose cell identities, signal, or neighbouring towers. The Android build shows their signal (positions aren't public on either platform).",
    "Nearby networks": "iOS doesn't permit scanning nearby Wi-Fi without a special Apple entitlement, so this isn't available here.",
    "Battery level": "The current battery charge, as a percentage.",
    "Battery state": "Whether the device is charging, full, or running on battery.",
    "Battery used": "How much battery a proof run consumed. iOS only exposes the charge level in coarse steps and no current sensor, so it can only be measured off-charger, and a single proof is usually below that resolution.",
    // GNSS · Sky (simulated on iOS — the OS withholds per-satellite GNSS data)
    "Sky dome": "A map of the sky: each dot is a satellite placed by its compass bearing and height above the horizon. Filled dots are used in the fix; dot size shows signal strength.",
    "Constellation": "Which satellite system this one belongs to — GPS (USA), Galileo (EU), GLONASS (Russia), BeiDou (China), QZSS (Japan). Seeing several systems is a sign of a genuine fix.",
    "SVID / PRN": "The satellite's ID number within its constellation — a name-plate that says exactly which satellite you're hearing.",
    "Band": "The radio frequency the satellite transmits on (e.g. GPS L1 near 1575 MHz). Modern phones track several bands at once for a better, harder-to-spoof fix.",
    "C/N0": "Carrier-to-noise density in dB-Hz — how clean the satellite's signal is. Higher is better: ~40+ is strong, under ~25 is weak.",
    "Azimuth": "The compass direction to the satellite (0° = North, 90° = East). With elevation, it pins the satellite's spot in the sky.",
    "Elevation": "How high the satellite sits above the horizon (0° = horizon, 90° = straight overhead). Higher satellites usually give a cleaner signal.",
    "Used in fix": "Whether this satellite is being used to compute the position — more satellites used means a stronger fix.",
    "Ephemeris": "Precise, short-lived orbit data broadcast by the satellite (valid ~4 h). The receiver needs it to use the satellite in a fix — 'cached' means it has a fresh copy.",
    "Almanac": "Coarse, long-lived orbit data for the whole constellation (valid for weeks). It helps the receiver find satellites fast, but isn't precise enough for the fix on its own.",
]

/// A small (i) button that opens a one-line explanation for a signal. Mirrors
/// the Android `InfoDot`. No-op when the key has no glossary entry.
struct InfoButton: View {
    let key: String
    @State private var show = false

    var body: some View {
        if let text = signalGlossary[key] {
            Button { show = true } label: {
                Image(systemName: "info.circle")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(key)")
            .alert(key, isPresented: $show) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(text)
            }
        }
    }
}

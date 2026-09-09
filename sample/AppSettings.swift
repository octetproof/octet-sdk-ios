import Foundation
import Combine

/// Sample preferences, persisted in `UserDefaults`. Split into two tiers:
///  - **release** toggles are harmless and always present;
///  - **debug** toggles (`semanticV2`, `verboseLogs`) are wrapped in `#if DEBUG`
///    everywhere they're read *and* set, so they are compiled out of a release
///    build entirely — a customer who discovers the hidden menu never sees them.
@MainActor
final class AppSettings: ObservableObject {
    // Release-tier
    @Published var showDebug: Bool { didSet { save(\.showDebug, showDebug) } }
    @Published var showDeviceTab: Bool { didSet { save(\.showDeviceTab, showDeviceTab) } }
    /// Applied at `Octet.start`; flipping it shows a "needs restart" hint.
    @Published var uploadsEnabled: Bool { didSet { save(\.uploadsEnabled, uploadsEnabled) } }
    /// Set once the 5-tap menu has been unlocked, so a small ⚙ affordance can
    /// reappear without advertising the gesture up front.
    @Published var devMenuUnlocked: Bool { didSet { save(\.devMenuUnlocked, devMenuUnlocked) } }

    #if DEBUG
    // Debug-tier — compiled OUT of release builds.
    @Published var semanticV2: Bool { didSet { save(\.semanticV2, semanticV2) } }
    @Published var verboseLogs: Bool { didSet { save(\.verboseLogs, verboseLogs) } }
    #endif

    private let d = UserDefaults.standard

    init() {
        showDebug = d.object(forKey: "showDebug") as? Bool ?? true
        showDeviceTab = d.object(forKey: "showDeviceTab") as? Bool ?? false
        uploadsEnabled = d.object(forKey: "uploadsEnabled") as? Bool ?? true
        devMenuUnlocked = d.object(forKey: "devMenuUnlocked") as? Bool ?? false
        #if DEBUG
        semanticV2 = d.object(forKey: "semanticV2") as? Bool ?? false
        verboseLogs = d.object(forKey: "verboseLogs") as? Bool ?? false
        #endif
    }

    private func save(_ key: KeyPath<AppSettings, Bool>, _ value: Bool) {
        // Persist under the property name — a tiny helper so each didSet is one line.
        let name: String
        switch key {
        case \AppSettings.showDebug: name = "showDebug"
        case \AppSettings.showDeviceTab: name = "showDeviceTab"
        case \AppSettings.uploadsEnabled: name = "uploadsEnabled"
        case \AppSettings.devMenuUnlocked: name = "devMenuUnlocked"
        #if DEBUG
        case \AppSettings.semanticV2: name = "semanticV2"
        case \AppSettings.verboseLogs: name = "verboseLogs"
        #endif
        default: return
        }
        d.set(value, forKey: name)
    }
}

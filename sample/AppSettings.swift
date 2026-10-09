import Foundation
import Combine

/// Sample preferences, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    /// Applied at `Octet.start`; flipping it shows a "needs restart" hint.
    @Published var uploadsEnabled: Bool {
        didSet { UserDefaults.standard.set(uploadsEnabled, forKey: "uploadsEnabled") }
    }

    init() {
        uploadsEnabled = UserDefaults.standard.object(forKey: "uploadsEnabled") as? Bool ?? true
    }
}

import SwiftUI

// The Octet sample app. License key comes from `LocalConfig.swift` (gitignored);
// copy `LocalConfig.swift.example` and paste your key. See README.

@main
struct OctetSampleApp: App {
    // The model owns the store + settings; all three are injected so views can
    // observe whichever they need (list updates on the store, tabs on settings).
    @StateObject private var model = AppModel(store: ProofStore(), settings: AppSettings())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.settings)
        }
    }
}

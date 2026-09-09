import SwiftUI
import UIKit

/// Tab shell — Generate · Verify (+ Device when enabled). Owns the hidden-menu
/// 5-tap gesture and the incoming `.octetproof` routing.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings

    @State private var showDevMenu = false
    @State private var taps = 0
    @State private var lastTap = Date.distantPast

    var body: some View {
        TabView {
            NavigationStack {
                GenerateView(onTitleTap: registerTitleTap, onOpenDevMenu: { showDevMenu = true })
            }
            .tabItem { Label("Generate", systemImage: "shield.lefthalf.filled") }

            NavigationStack { VerifyView() }
                .tabItem { Label("Verify", systemImage: "checkmark.seal") }

            if settings.showDeviceTab {
                NavigationStack { DeviceInfoView() }
                    .tabItem { Label("Device", systemImage: "cpu") }
            }
        }
        .tint(Theme.accent)
        .task { model.bootstrap() }
        .sheet(isPresented: $showDevMenu) { DevSettingsView() }
        .sheet(item: $model.pendingImport) { env in ImportPreviewView(env: env) }
        .onOpenURL { url in
            if let env = ProofFile.readEnvelope(at: url) { model.pendingImport = env }
        }
    }

    /// 5 taps on the title within a 2-second window unlocks the dev menu.
    private func registerTitleTap() {
        let now = Date()
        if now.timeIntervalSince(lastTap) > 2 { taps = 0 }
        lastTap = now
        taps += 1
        if taps >= 5 {
            taps = 0
            settings.devMenuUnlocked = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showDevMenu = true
        }
    }
}

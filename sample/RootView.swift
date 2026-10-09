import SwiftUI

/// Tab shell — Generate · Verify, plus the incoming `.octetproof` routing.
struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { GenerateView() }
                .tabItem { Label("Generate", systemImage: "shield.lefthalf.filled") }

            NavigationStack { VerifyView() }
                .tabItem { Label("Verify", systemImage: "checkmark.seal") }

            ChannelTabs()
        }
        .tint(Theme.accent)
        .task { model.bootstrap() }
        .channelChrome()
        .sheet(item: $model.pendingImport) { env in ImportPreviewView(env: env) }
        .onOpenURL { url in
            if let env = ProofFile.readEnvelope(at: url) { model.pendingImport = env }
        }
    }
}

import SwiftUI
import Network
import OctetSDK

/// The (opt-in) Device Info tab — capabilities + states, grouped. No identifiers.
struct DeviceInfoView: View {
    @EnvironmentObject var model: AppModel
    @State private var networkType = "checking…"
    private let monitor = NWPathMonitor()

    var body: some View {
        List {
            ForEach(DeviceInfo.categories()) { cat in
                Section {
                    ForEach(cat.rows) { r in kv(r.key, r.value) }
                } header: { Label(cat.title, systemImage: cat.icon) }
            }
            Section {
                kv("SDK", "v\(Octet.sdkVersion)")
                kv("license", model.licenseLine.isEmpty ? "—" : model.licenseLine)
            } header: { Label("SDK / License", systemImage: "shippingbox") }
            Section {
                kv("connection", networkType)
            } header: { Label("Network", systemImage: "wifi") }
        }
        .navigationTitle("Device")
        .task {
            monitor.pathUpdateHandler = { path in
                let t: String
                if path.status != .satisfied { t = "offline" }
                else if path.usesInterfaceType(.wifi) { t = "Wi-Fi" }
                else if path.usesInterfaceType(.cellular) { t = "Cellular" }
                else if path.usesInterfaceType(.wiredEthernet) { t = "Wired" }
                else { t = "other" }
                Task { @MainActor in networkType = t }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
        .onDisappear { monitor.cancel() }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }.font(.subheadline)
    }
}

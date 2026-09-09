import SwiftUI
import OctetSDK

/// The hidden developer menu (unlocked by 5 taps on the title). Release builds
/// see ONLY the benign top section; the `#if DEBUG` section below is compiled out
/// of release entirely, so a customer who discovers this menu can never reach the
/// SDK-internal toggles.
struct DevSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Show debug output", isOn: $settings.showDebug)
                    Toggle("Device info tab", isOn: $settings.showDeviceTab)
                }
                Section {
                    Toggle("Upload proofs", isOn: $settings.uploadsEnabled)
                } footer: {
                    Text("↻ Applies on next launch (the upload URL is set when the SDK starts).")
                }
                Section("Data") {
                    Button(role: .destructive) { model.store.clear() } label: { Text("Clear stored proofs") }
                    Button {
                        UIPasteboard.general.string = diagnostics()
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy diagnostics", systemImage: "doc.on.doc") }
                }

                Section {
                    NavigationLink { SensorsView() } label: {
                        Label("Sensors", systemImage: "sensor.tag.radiowaves.forward")
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("A live readout of this device's own sensors (motion, location quality, radio). Public-framework data only — no SDK internals.")
                }

                #if DEBUG
                Section {
                    Toggle("Semantic-binding v2", isOn: $settings.semanticV2)
                    Toggle("Verbose SDK logs", isOn: $settings.verboseLogs)
                    if settings.verboseLogs {
                        NavigationLink { SDKLogView() } label: {
                            Label("View SDK log", systemImage: "text.alignleft")
                        }
                    }
                } header: {
                    Text("Developer (debug builds only)")
                } footer: {
                    Text("Streams the SDK's public log (lifecycle, verdicts, errors) into the app. This whole section is compiled out of release builds — customers never see it.")
                }
                .onChange(of: settings.verboseLogs) { _, _ in model.applyVerboseLogging() }
                #endif
            }
            .navigationTitle("Developer settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// A sanitized diagnostics blob safe to paste into a support ticket:
    /// capabilities + states only, never an identifier, key, token, or coordinate.
    private func diagnostics() -> String {
        var lines = ["Octet Sample diagnostics", "SDK v\(Octet.sdkVersion)",
                     "license: \(model.licenseLine.isEmpty ? "—" : model.licenseLine)"]
        for cat in DeviceInfo.categories() {
            lines.append("[\(cat.title)]")
            for r in cat.rows { lines.append("  \(r.key): \(r.value)") }
        }
        return lines.joined(separator: "\n")
    }
}

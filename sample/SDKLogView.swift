#if DEBUG
import SwiftUI

/// Live view of the SDK's public log stream, reached from the hidden Dev menu
/// when "Verbose SDK logs" is on. DEBUG-only (compiled out of release). Shows
/// `PublicLog` events — the SDK's PII-disciplined public surface (lifecycle,
/// verdicts, errors); internal signals / scores never reach here.
struct SDKLogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            if model.sdkLog.isEmpty {
                Text("No SDK log lines yet — generate a proof or relaunch to capture lifecycle events.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.sdkLog) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.text).font(Theme.mono(11))
                        Text(line.time, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
        }
        .navigationTitle("SDK log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        UIPasteboard.general.string = model.sdkLog.map(\.text).joined(separator: "\n")
                    } label: { Label("Copy all", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { model.clearSDKLog() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
#endif

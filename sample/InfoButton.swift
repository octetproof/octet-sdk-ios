import SwiftUI

/// One-line explanations for the (i) buttons.
let coreGlossary: [String: String] = [
    "Battery used": "How much battery a proof run consumed. iOS only exposes the charge level in coarse steps and no current sensor, so it can only be measured off-charger, and a single proof is usually below that resolution.",
]

/// A small (i) button that opens a one-line explanation for a signal. Mirrors
/// the Android `InfoDot`. No-op when the key has no glossary entry.
struct InfoButton: View {
    let key: String
    @State private var show = false

    var body: some View {
        if let text = Self.text(for: key) {
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

    private static func text(for key: String) -> String? {
        coreGlossary[key] ?? Channel.glossaryText(for: key)
    }
}

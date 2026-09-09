import SwiftUI
import OctetSDK

/// Shown when a `.octetproof` arrives (AirDrop / Files / share). The proof is
/// auto-verified and previewed — never silently added. Duplicate bytes are
/// recognised so the list never grows a second copy.
struct ImportPreviewView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let env: ProofEnvelope

    @State private var verification: ProofVerification?

    private var label: String { env.region.count == 2 ? countryName(for: env.region) : env.region }
    private var alreadyHave: Bool { model.store.proofs.contains { $0.proofB64 == env.proofB64 } }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.largeTitle).foregroundStyle(Theme.accent)
                Text("Import proof?").font(.title3.bold())
                Text("\(label) · \(ViewRawView.stamp(env.generatedAtMs))")
                    .font(.subheadline).foregroundStyle(.secondary)

                if let v = verification {
                    HStack(spacing: Theme.Space.s) {
                        StatusDot(kind: v.verdict == .valid ? .ok : v.verdict == .invalid ? .bad : .warn)
                        Text(v.verdict == .valid ? "VALID" : v.verdict == .invalid ? "INVALID" : "INCONCLUSIVE")
                            .font(.headline)
                    }
                    Text("verified on import").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack { ProgressView(); Text("verifying…").foregroundStyle(.secondary) }
                }

                if alreadyHave {
                    Text("Already imported").font(.subheadline).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Spacer()
                Button {
                    _ = model.importEnvelope(env)
                    dismiss()
                } label: {
                    Text(alreadyHave ? "Keep" : "Add to my proofs").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(alreadyHave)

                Button("Cancel") { dismiss() }
            }
            .padding(Theme.Space.xl)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                verification = Octet.verify(proofBytes: Data(base64Encoded: env.proofB64) ?? Data())
            }
        }
    }
}

import SwiftUI

/// Read-only "view raw" sheet — the decoded PUBLIC fields of a proof plus its
/// shareable bytes. Deliberately shows only what `LocationProof` exposes as its
/// public surface + the base64; the sensitive internals stay inside `proofBytes`
/// and are never rendered.
struct ViewRawView: View {
    let proof: StoredProof

    var body: some View {
        List {
            Section("Proof (public fields)") {
                row("region", proof.regionLabel + (proof.regionISO.map { " (\($0))" } ?? ""))
                row("proof level", proof.level)
                row("generated", Self.stamp(proof.generatedAtMs))
                row("confidence", String(format: "%.2f (%@)", proof.confidenceScore, proof.bucket.rawValue))
                if let r = proof.predicateResult { row("predicate", r) }
                row("source", proof.imported ? "imported" : "generated on this device")
                row("size", "\(proof.sizeBytes) bytes")
            }
            Section("Bytes (base64 — shareable, no secrets)") {
                Text(Self.preview(proof.proofB64))
                    .font(Theme.mono(11)).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button { UIPasteboard.general.string = proof.proofB64 } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Spacer()
                    if let url = ProofFile.tempEnvelopeURL(for: proof) {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
                .font(.subheadline).tint(Theme.accent)
            }
        }
        .navigationTitle("Raw proof")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) }
            .font(.subheadline)
    }

    static func stamp(_ ms: Int64) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) + " UTC"
    }
    static func preview(_ b64: String) -> String {
        b64.count <= 96 ? b64 : String(b64.prefix(48)) + "…" + String(b64.suffix(24))
    }
}

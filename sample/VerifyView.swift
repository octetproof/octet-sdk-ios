import SwiftUI
import UniformTypeIdentifiers

/// The Verify tab: entry points (verify latest / paste / import) above the full
/// list of every proof stored on the device. Tap a row to verify it.
struct VerifyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: ProofStore

    @State private var showPaste = false
    @State private var showImporter = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                if let latest = store.latest {
                    NavigationLink { VerifyDetailView(proof: latest) } label: {
                        Label("Verify latest", systemImage: "bolt.badge.checkmark")
                    }
                }
                Button { showPaste = true } label: { Label("Paste proof bytes", systemImage: "doc.on.clipboard") }
                Button { showImporter = true } label: { Label("Import proof", systemImage: "square.and.arrow.down") }
            }

            Section("Stored on device (\(store.proofs.count))") {
                if store.proofs.isEmpty {
                    Text("No proofs yet — generate one, or import a .octetproof file.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(store.sorted) { proof in
                        NavigationLink { VerifyDetailView(proof: proof) } label: { ProofRow(proof: proof) }
                            .swipeActions {
                                Button(role: .destructive) { store.delete(proof) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                if let url = ProofFile.tempEnvelopeURL(for: proof) {
                                    ShareLink("Export / Share", item: url)
                                }
                                Button { /* handled via NavigationLink for raw */ } label: { Label("Open to view raw", systemImage: "curlybraces") }
                                    .disabled(true)
                                Button(role: .destructive) { store.delete(proof) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }

            if !store.proofs.isEmpty {
                Section {
                    Button(role: .destructive) { store.clear() } label: { Text("Clear all stored proofs") }
                }
            }
        }
        .navigationTitle("Verify")
        .sheet(isPresented: $showPaste) { PasteVerifyView() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [ProofFile.utType, .json, .data]) { result in
            handleImport(result)
        }
        .overlay(alignment: .bottom) { if let t = toast { ToastView(text: t) } }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let env = ProofEnvelope.decode(data) else {
            flash("Not a valid .octetproof file"); return
        }
        // Route through the same preview the AirDrop path uses.
        model.pendingImport = env
    }

    private func flash(_ s: String) {
        toast = s
        Task { try? await Task.sleep(for: .seconds(2)); toast = nil }
    }
}

// MARK: - Row

struct ProofRow: View {
    let proof: StoredProof

    private var kind: StatusKind {
        switch proof.predicateResult {
        case "inside": return .ok
        case "outside": return .bad
        case "indeterminate": return .warn
        default: return .notChecked   // imported (unknown until verified)
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            StatusDot(kind: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(proof.regionLabel).font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Chip(text: proof.bucket.rawValue, tint: proof.bucket.tintKind.color)
                    if proof.imported { Chip(text: "imported", tint: Theme.accent) }
                    Text(Self.short(proof.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    static func short(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"; return f.string(from: d)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule()).padding(.bottom, 24)
    }
}

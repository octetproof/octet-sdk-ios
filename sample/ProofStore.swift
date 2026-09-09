import Foundation
import Combine

/// The sample's own persistent list of proofs (the SDK exposes no proof store).
/// Backed by a single JSON file in Documents; survives relaunch. Everything it
/// holds is non-sensitive (see `StoredProof`).
@MainActor
final class ProofStore: ObservableObject {
    @Published private(set) var proofs: [StoredProof] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("proofs.json")
    }()

    init() { load() }

    /// Newest first — what every list shows.
    var sorted: [StoredProof] { proofs.sorted { $0.createdAt > $1.createdAt } }

    var latest: StoredProof? { sorted.first }

    func contains(_ proof: StoredProof) -> Bool {
        proofs.contains { $0.contentKey == proof.contentKey }
    }

    /// Add a proof unless byte-identical to one already stored. Returns false if
    /// it was a duplicate (so import can say "already imported").
    @discardableResult
    func add(_ proof: StoredProof) -> Bool {
        guard !contains(proof) else { return false }
        proofs.append(proof)
        save()
        return true
    }

    func delete(_ proof: StoredProof) {
        proofs.removeAll { $0.id == proof.id }
        save()
    }

    func clear() {
        proofs.removeAll()
        save()
    }

    // MARK: - persistence

    private func load() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601 // must match save()'s encoder
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? dec.decode([StoredProof].self, from: data)
        else { return }
        proofs = decoded
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(proofs) else { return }
        // Written to the app sandbox only; excluded from iCloud/iTunes backup is
        // unnecessary here (proofs are shareable, not secret).
        try? data.write(to: fileURL, options: .atomic)
    }
}

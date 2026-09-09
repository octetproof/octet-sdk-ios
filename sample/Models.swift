import Foundation

// On-device persistence models. Deliberately SDK-free + Codable: a StoredProof
// is what the sample keeps for each proof it generated or imported (the SDK has
// no "list proofs" API). Only non-sensitive fields are stored — never a raw
// coordinate, key, token, or device identifier.

/// One proof the sample is holding on to. `proofB64` is the shareable serialized
/// proof; everything else is convenience metadata for the list + cards.
struct StoredProof: Codable, Identifiable, Hashable {
    let id: String                 // local UUID (not the proof's internal id)
    let proofB64: String           // base64-standard of proofBytes (shareable)
    let regionISO: String?         // ISO alpha-2 for country proofs, else nil
    let regionLabel: String        // display, e.g. "Germany"
    let level: String              // proof level, e.g. "ON_EARTH" / "COUNTRY"
    let generatedAtMs: Int64       // the proof's own signed timestamp
    let createdAt: Date            // when this device stored it
    let confidenceScore: Double    // ConfidenceSummary.overallScore
    let predicateResult: String?   // "inside" / "outside" / "indeterminate"; nil if imported
    let imported: Bool             // arrived via share/AirDrop rather than generated here
    let sizeBytes: Int

    var proofBytes: Data { Data(base64Encoded: proofB64) ?? Data() }
    var bucket: ConfidenceBucket { ConfidenceBucket(score: confidenceScore) }

    /// Stable content key for de-duplication (same proof bytes = same proof).
    var contentKey: String { proofB64 }
}

/// Confidence tier — the sample buckets `overallScore` so the UI can read at a
/// glance without exposing internal sub-scores.
enum ConfidenceBucket: String {
    case high = "HIGH", medium = "MEDIUM", low = "LOW"

    init(score: Double) {
        switch score {
        case 0.8...: self = .high
        case 0.5..<0.8: self = .medium
        default: self = .low
        }
    }

    var tintKind: StatusKind {
        switch self {
        case .high: return .ok
        case .medium: return .warn
        case .low: return .bad
        }
    }
}

/// The `.octetproof` interchange envelope — what travels over AirDrop / Nearby
/// Share / any OS share target. Versioned + self-describing (so the receiving
/// device shows region + time immediately), and carries ONLY the shareable proof
/// bytes plus benign metadata — no device or license data rides along.
struct ProofEnvelope: Codable, Identifiable {
    let v: Int
    let proofB64: String
    let region: String        // ISO alpha-2 or a display label
    let generatedAtMs: Int64

    /// For `.sheet(item:)` — the proof bytes uniquely identify the envelope.
    var id: String { proofB64 }

    enum CodingKeys: String, CodingKey {
        case v
        case proofB64 = "proof_b64"
        case region
        case generatedAtMs = "generated_at"
    }

    static let currentVersion = 1

    init(proofB64: String, region: String, generatedAtMs: Int64) {
        self.v = Self.currentVersion
        self.proofB64 = proofB64
        self.region = region
        self.generatedAtMs = generatedAtMs
    }

    /// Encode to the canonical `.octetproof` file bytes (sorted keys, stable).
    func fileData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try enc.encode(self)
    }

    /// Decode from received `.octetproof` bytes; nil if it isn't a valid envelope
    /// (or is a future major version this build doesn't understand).
    static func decode(_ data: Data) -> ProofEnvelope? {
        guard let env = try? JSONDecoder().decode(ProofEnvelope.self, from: data),
              env.v == currentVersion,
              Data(base64Encoded: env.proofB64) != nil
        else { return nil }
        return env
    }
}

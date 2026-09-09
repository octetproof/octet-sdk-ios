import Foundation
import UniformTypeIdentifiers

/// The `.octetproof` interchange type + helpers for share/import. The exported
/// type is declared in `project.yml` (→ Info.plist) so AirDrop / Nearby Share /
/// Files can carry it and route incoming files back to the app.
enum ProofFile {
    /// Must match the identifier declared in Info.plist (UTExportedTypeDeclarations).
    static let identifier = "com.octetproof.proof"
    static let fileExtension = "octetproof"

    static let utType: UTType = UTType(exportedAs: identifier, conformingTo: .json)

    /// Write a proof's envelope to a temp `.octetproof` file and return the URL
    /// for ShareLink / the share sheet. nil only if encoding fails.
    static func tempEnvelopeURL(for proof: StoredProof) -> URL? {
        let env = ProofEnvelope(proofB64: proof.proofB64,
                                region: proof.regionISO ?? proof.regionLabel,
                                generatedAtMs: proof.generatedAtMs)
        guard let data = try? env.fileData() else { return nil }
        let name = "octet-\(proof.regionISO ?? "proof")-\(proof.generatedAtMs).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Read + decode an incoming `.octetproof` file URL (handles security scope).
    static func readEnvelope(at url: URL) -> ProofEnvelope? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ProofEnvelope.decode(data)
    }
}

import SwiftUI
import OctetSDK

/// Verify one stored proof with `Octet.verify` and show the grouped result.
struct VerifyDetailView: View {
    @EnvironmentObject var model: AppModel
    let proof: StoredProof

    @State private var result: ProofVerification?
    // What to check the proof's location claim against. Defaults to "Any region"
    // (nil → the three region checks are NOT-CHECKED); the user actively picks a
    // country to run them. NOT the isWithin query region.
    @State private var expectedISO: String? = nil

    var body: some View {
        List {
            Section {
                // Pushed, searchable — not an inline Picker: its menu rebuilds and
                // loses scroll position whenever AppModel republishes (location).
                NavigationLink {
                    RegionCheckPickerView(selectedISO: $expectedISO)
                } label: {
                    HStack {
                        Text("Check against region")
                        Spacer()
                        Text(expectedISO.map { countryName(for: $0) } ?? "Any region")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("This proof claims the device's location at **\(levelPhrase)** level — it reveals nothing finer. Pick a region to check that claim against: it passes when the proof's location is inside the region and fails when it isn't. “Any region” leaves the three region checks unverified.")
            }

            if let v = result {
                Section {
                    HStack(spacing: Theme.Space.s) {
                        StatusDot(kind: verdictKind(v))
                        VStack(alignment: .leading) {
                            Text(verdictLabel(v)).font(.headline)
                            Text("authentic: \(v.isAuthentic ? "yes" : "no")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                group("PASSED", v.checks.filter { $0.status == .pass }, .ok)
                group("WARN", v.checks.filter { $0.status == .warn }, .warn)
                group("NOT-CHECKED", v.checks.filter { $0.status == .notChecked }, .notChecked)
                group("FAILED", v.checks.filter { $0.status == .fail }, .bad)

                Section {
                    NavigationLink { ViewRawView(proof: proof) } label: { Label("View raw", systemImage: "curlybraces") }
                    if let url = ProofFile.tempEnvelopeURL(for: proof) {
                        ShareLink(item: url) { Label("Export / Share", systemImage: "square.and.arrow.up") }
                    }
                    Button { result = model.verify(proof, expectedISO: expectedISO) } label: {
                        Label("Re-verify", systemImage: "arrow.clockwise")
                    }
                }
            } else {
                Section { HStack { ProgressView(); Text("Verifying…").foregroundStyle(.secondary) } }
            }
        }
        .navigationTitle(proof.regionLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task { if result == nil { result = model.verify(proof, expectedISO: expectedISO) } }
        .onChange(of: expectedISO) { _, iso in result = model.verify(proof, expectedISO: iso) }
    }

    @ViewBuilder
    private func group(_ title: String, _ checks: [ProofCheck], _ kind: StatusKind) -> some View {
        if !checks.isEmpty {
            Section("\(title) (\(checks.count))") {
                ForEach(checks, id: \.name) { c in
                    DisclosureGroup {
                        // For a check that couldn't run, show a plain-language reason
                        // + what to change; otherwise the SDK's own short detail.
                        let explainer = kind == .notChecked ? notCheckedExplainer(c.name) : ""
                        Text(explainer.isEmpty ? c.detail : explainer)
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            StatusDot(kind: kind)
                            Text(c.name).font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    /// Plain-language, one-line "why it didn't run + what to change" for the
    /// checks the on-device verifier can't perform with the given inputs. Sample
    /// copy only — no coordinates, keys, tokens, or SDK internals. Falls back to
    /// the SDK's own detail for anything without curated copy.
    private func notCheckedExplainer(_ name: String) -> String {
        switch name {
        case "region-claim":
            return "Checks the proof's region matches the one you expect — verify against an expected region to run it."
        case "region-type":
            return "Checks the region kind (country, city, …) matches what you expect — verify against an expected region to run it."
        case "region-contains":
            return "Checks the location falls inside the expected region — verify against an expected region to run it."
        case "hardware-attestation":
            return "Confirms the proof came from genuine device hardware — generate one on a real device with attestation enabled to run it."
        case "replay-binding":
            return "The one-time replay tag travels with an uploaded proof, not the saved file, so there's nothing here to check."
        case "replay-ledger":
            return "Confirms this proof hasn't been reused — an online check, so it can't run on the device alone."
        case "revocation":
            return "Confirms the signing key hasn't been revoked — an online check, so it isn't done on the device."
        default:
            return ""
        }
    }

    private func verdictKind(_ v: ProofVerification) -> StatusKind {
        switch v.verdict { case .valid: return .ok; case .invalid: return .bad; case .inconclusive: return .warn }
    }
    private func verdictLabel(_ v: ProofVerification) -> String {
        switch v.verdict { case .valid: return "VALID"; case .invalid: return "INVALID"; case .inconclusive: return "INCONCLUSIVE" }
    }

    /// The proof's granularity, in words ("country" / "city" / …) for the note.
    private var levelPhrase: String {
        let l = proof.level.lowercased()
        return (l.isEmpty || l == "—") ? "the recorded" : l
    }
}

// MARK: - Paste-to-verify

struct PasteVerifyView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: ProofVerification?

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste base64 proof bytes") {
                    TextEditor(text: $text).font(Theme.mono(12)).frame(minHeight: 120)
                }
                Section {
                    Button("Verify") { verify() }
                        .disabled(Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                }
                if let v = result {
                    Section("Result") {
                        Text(v.verdict == .valid ? "✓ VALID" : v.verdict == .invalid ? "✗ INVALID" : "? INCONCLUSIVE")
                            .font(.headline)
                        Text("authentic: \(v.isAuthentic ? "yes" : "no")").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Paste & verify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func verify() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed) else { return }
        result = Octet.verify(proofBytes: data)
    }
}

// MARK: - "Check against region" picker (searchable, pushed)

/// Region selector for the Verify screen. A pushed, searchable `List` (not an
/// inline Picker, whose menu rebuilds + loses scroll on every `AppModel` publish),
/// with an "Any region" option that clears the check.
struct RegionCheckPickerView: View {
    @Binding var selectedISO: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Country] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return demoCountries }
        return demoCountries.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            if query.isEmpty {
                row(label: "Any region — don't check", isSelected: selectedISO == nil) {
                    selectedISO = nil; dismiss()
                }
            }
            ForEach(filtered) { c in
                row(label: "\(c.name) (\(c.id))", isSelected: selectedISO == c.id) {
                    selectedISO = c.id; dismiss()
                }
            }
        }
        .searchable(text: $query, prompt: "Search country")
        .navigationTitle("Check against region")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(label: String, isSelected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
        }
    }
}

import SwiftUI
import MapKit
import OctetSDK

/// The Generate tab: the live (approximated) pipeline with timings, region
/// picker, map, the Generate button, the predicate result card, and the
/// expandable sanitized debug feed.
struct GenerateView: View {
    @EnvironmentObject var model: AppModel
    var onTitleTap: () -> Void
    var onOpenDevMenu: () -> Void

    @State private var showDebug = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                PipelineCard(steps: model.steps, state: model.sdkState)
                if let notice = model.licenseNotice {
                    Text(notice).font(.footnote)
                        .padding(Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                regionRow
                map
                generateButton
                forceFreshRow
                if let result = model.lastResult {
                    ResultCard(result: result)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                debugSection
            }
            .padding(Theme.Space.l)
            // A fresh run is unmistakable: the old card animates out on tap and the
            // new one scales in when generation finishes (keyed on isGenerating,
            // which flips in the same update as the new result).
            .animation(.easeOut(duration: 0.35), value: model.isGenerating)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Octetproof").font(.title2.bold())
                Text("· Sample").font(.title3).foregroundStyle(.secondary)
                Spacer()
                if model.settings.devMenuUnlocked {
                    Button(action: onTitleTap) {
                        Image(systemName: "gearshape").foregroundStyle(.secondary)
                    }.accessibilityLabel("Developer settings")
                }
            }
            Text("SDK v\(Octet.sdkVersion) · \(model.licenseLine.isEmpty ? model.sdkState.label : model.licenseLine)")
                .font(.caption).foregroundStyle(.secondary)
        }
        // 5 taps on the title area unlocks the hidden dev menu.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTitleTap)
    }

    private var regionRow: some View {
        HStack {
            Text("Region").foregroundStyle(.secondary)
            Spacer()
            // A pushed, searchable picker — not a .menu Picker: the menu rebuilds
            // (and its scroll resets) every time the map / location republishes.
            NavigationLink {
                CountryPickerView()
            } label: {
                HStack(spacing: 4) {
                    Text("\(model.selectedCountry.name) (\(model.selectedCountry.id))")
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private var map: some View {
        Map(position: $model.cameraPosition) {
            if let loc = model.userLocation {
                Marker("You", coordinate: loc).tint(Theme.accent)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var generateButton: some View {
        Button {
            Task { await model.generate() }
        } label: {
            HStack {
                if model.isGenerating { ProgressView().tint(.white) }
                Text(model.isGenerating ? "Generating…" : "Generate Proof").bold()
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent).tint(Theme.accent)
        .disabled(!model.isReady || model.isGenerating)
    }

    private var forceFreshRow: some View {
        Toggle(isOn: $model.forceFresh) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Force fresh proof").font(.subheadline)
                Text("Bypass the cache and mint a brand-new proof each time")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(Theme.accent)
        .disabled(model.isGenerating)
    }

    private var debugSection: some View {
        DisclosureGroup(isExpanded: $showDebug) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.debug.suffix(50)) { line in
                    Text("\(Self.hms(line.time))  \(line.text)")
                        .font(Theme.mono(11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("no coordinates · keys · tokens · IDs shown")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
            }
            .padding(.top, Theme.Space.s)
        } label: {
            Label("Debug output (\(model.debug.count))", systemImage: "terminal")
                .font(.subheadline)
        }
        .tint(Theme.accent)
        .opacity(model.settings.showDebug ? 1 : 0)
        .frame(height: model.settings.showDebug ? nil : 0)
        .disabled(!model.settings.showDebug)
    }

    static func hms(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}

// MARK: - Pipeline card

struct PipelineCard: View {
    let steps: [PipelineStep]
    let state: AppModel.SDKState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("PIPELINE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .tracking(1)
                ForEach(steps) { step in
                    HStack(spacing: Theme.Space.s) {
                        StatusDot(kind: step.kind)
                        Text(step.label)
                            .font(.subheadline)
                            .foregroundStyle(step.state == .pending ? .secondary : .primary)
                        Spacer()
                        if let s = step.seconds {
                            Text(String(format: "%.1fs", s))
                                .font(Theme.mono(12)).foregroundStyle(.secondary)
                        } else if step.state == .active {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Result card (predicate answer, not a verification)

struct ResultCard: View {
    let result: GenerateResult

    private var kind: StatusKind {
        switch result.result { case .yes: return .ok; case .no: return .bad; case .indeterminate: return .warn }
    }
    private var headline: String {
        switch result.result {
        case .yes: return "Inside \(result.regionLabel)"
        case .no: return "Outside \(result.regionLabel)"
        case .indeterminate: return "Indeterminate"
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    StatusDot(kind: kind)
                    Text(headline).font(.headline)
                }
                HStack(spacing: Theme.Space.s) {
                    Chip(text: result.bucket.rawValue, tint: result.bucket.tintKind.color)
                    Text(String(format: "%.2f", result.score)).font(Theme.mono(12)).foregroundStyle(.secondary)
                    if result.stored != nil {
                        if result.fresh { Chip(text: "✓ fresh", tint: Theme.pass) }
                        else { Chip(text: "cached") }
                    }
                }
                if let b = result.battery { batteryLine(b) }
                if let stored = result.stored {
                    HStack {
                        NavigationLink { ViewRawView(proof: stored) } label: { Text("View raw") }
                        Spacer()
                        NavigationLink { VerifyDetailView(proof: stored) } label: { Text("Verify ▸") }
                    }
                    .font(.subheadline).tint(Theme.accent).padding(.top, 2)
                } else {
                    Text("No proof produced under current conditions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Per-proof battery cost. iOS can only report a coarse level drop (no charge
    /// counter), so most runs read "below resolution" — measured only off-charger.
    @ViewBuilder private func batteryLine(_ b: BatteryCost) -> some View {
        let text: String = {
            if b.charging {
                return "Battery: shown only off-charger — unplug to measure a proof's consumption"
            } else if let pct = b.pct {
                return String(format: "Battery: ~%d%% this run · %.1fs", pct, b.durationSec)
            } else {
                return String(format: "Battery: below iOS's ~1%% level resolution this run · %.1fs", b.durationSec)
            }
        }()
        HStack(spacing: 4) {
            Text(text).font(.footnote).foregroundStyle(.secondary)
            InfoButton(key: "Battery used")
        }
    }
}

// MARK: - Country picker (searchable, pushed)

/// The region selector. A pushed, searchable `List` rather than an inline
/// `.menu` Picker — the menu rebuilds and loses its scroll position whenever the
/// map / location updates republish `AppModel`, which made long scrolls jump.
struct CountryPickerView: View {
    @EnvironmentObject var model: AppModel
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
        List(filtered) { c in
            Button {
                model.userSelectedCountry(c)
                dismiss()
            } label: {
                HStack {
                    Text("\(c.name) (\(c.id))").foregroundStyle(.primary)
                    Spacer()
                    if c == model.selectedCountry {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search country")
        .navigationTitle("Region")
        .navigationBarTitleDisplayMode(.inline)
    }
}

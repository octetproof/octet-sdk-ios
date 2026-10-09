import SwiftUI

/// GNSS · Sky — a sky map of the satellites overhead (a 2.5D dome), a satellite
/// table, and a tap-through detail card per satellite. Mirrors the Android build's
/// `GnssSkyScreen` visually.
///
/// **Platform honesty:** iOS public APIs do NOT expose per-satellite GNSS data
/// (there is no `GnssStatus` equivalent — Core Location gives only the fused fix
/// and its accuracy). So this sky is a **simulated, representative** snapshot,
/// clearly badged as such — never presented as live device data. The Android
/// build shows the real thing. The generator is our own (a seeded, deterministic
/// spread), so the picture is stable and copyright-clean.
struct GnssSkyView: View {
    // Generated once, so the sky is stable while the screen is open.
    @State private var sats: [SimSat] = SimSat.representativeSky()
    @State private var selected: SimSat?

    private var usedCount: Int { sats.filter { $0.usedInFix }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    SkyDomeCanvas(sats: sats) { selected = $0 }
                        .aspectRatio(1.35, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    SkyDomeLegend(sats: sats)
                    Text("\(sats.count) placed · \(usedCount) used in fix · strongest "
                         + "\(Int(sats.map(\.cn0).max() ?? 0)) dBHz. Overhead = top of the dome, "
                         + "rim = horizon. Filled = used in fix, size = signal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                HStack(spacing: 6) {
                    Text("Sky dome")
                    InfoButton(key: "Sky dome")
                }
            }

            Section {
                satHeader
                ForEach(sats.sorted { $0.cn0 > $1.cn0 }) { s in
                    Button { selected = s } label: { SatRow(sat: s) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Satellites")
            } footer: {
                Text("Tap a satellite for detail. Eph = broadcast ephemeris cached. "
                     + "Simulated, representative data — iOS withholds per-satellite GNSS.")
            }
        }
        .navigationTitle("GNSS · Sky")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { simulatedBanner }
        .sheet(item: $selected) { SatelliteDetailSheet(sat: $0) }
    }

    private var simulatedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
            Text("Simulated sky — iOS doesn't expose per-satellite GNSS. The fix itself is real.")
                .font(.caption2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(Theme.warn)
        .background(Theme.warn.opacity(0.12))
    }

    // MARK: - satellite table

    private var satHeader: some View {
        HStack(spacing: 0) {
            hcell("Sat", 56)
            hcell("Band", 74)
            hcell("C/N0", nil)
            hcell("Elev", 46)
            hcell("Fix", 32)
            hcell("Eph", 34)
        }
        .foregroundStyle(.secondary)
        .font(.caption2)
    }

    private func hcell(_ t: String, _ w: CGFloat?) -> some View {
        Group {
            if let w { Text(t).frame(width: w, alignment: .leading) }
            else { Text(t).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

// MARK: - satellite row

private struct SatRow: View {
    let sat: SimSat
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(sat.color).frame(width: 8, height: 8)
                Text(sat.label).font(Theme.mono(12))
            }
            .frame(width: 56, alignment: .leading)

            Text(sat.band).font(.caption).foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            HStack(spacing: 6) {
                Cn0Bar(cn0: sat.cn0)
                Text("\(Int(sat.cn0))").font(Theme.mono(12))
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 8)

            Text("\(Int(sat.elevationDeg))°").font(Theme.mono(12))
                .frame(width: 46, alignment: .leading)
            Text(sat.usedInFix ? "✓" : "·")
                .foregroundStyle(sat.usedInFix ? Theme.pass : Color.secondary)
                .fontWeight(.bold)
                .frame(width: 32, alignment: .leading)
            Text(sat.hasEphemeris ? "E" : (sat.hasAlmanac ? "a" : "·"))
                .font(.caption)
                .foregroundStyle(sat.hasEphemeris ? Theme.accent : Color.secondary)
                .frame(width: 34, alignment: .leading)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// C/N0 bar, ~0…50 dBHz; green strong, amber ok, red weak.
private struct Cn0Bar: View {
    let cn0: Double
    var body: some View {
        let frac = min(max(cn0 / 50.0, 0), 1)
        let tint: Color = frac > 0.66 ? Theme.pass : (frac > 0.33 ? Theme.warn : Theme.fail)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(tint).frame(width: geo.size.width * frac)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - detail sheet

private struct SatelliteDetailSheet: View {
    let sat: SimSat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                detail("Constellation", sat.constellation)
                detail("SVID / PRN", "\(sat.svid)")
                detail("Band", sat.band)
                detail("C/N0", "\(Int(sat.cn0)) dBHz")
                detail("Azimuth", "\(Int(sat.azimuthDeg))°")
                detail("Elevation", "\(Int(sat.elevationDeg))°")
                detail("Used in fix", sat.usedInFix ? "yes" : "no")
                detail("Ephemeris", sat.hasEphemeris ? "cached" : "no")
                detail("Almanac", sat.hasAlmanac ? "cached" : "no")
                Section {
                    Text("Simulated, representative values — iOS withholds per-satellite GNSS "
                         + "data, so this illustrates what a real fix looks like rather than "
                         + "reporting live satellites. Orbit params (altitude · velocity · "
                         + "period) are shown in the 3D Orbits view, computed from published TLEs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(sat.constellation) \(sat.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).foregroundStyle(.secondary)
            InfoButton(key: k)
            Spacer()
            Text(v).font(Theme.mono(13))
        }
        .font(.subheadline)
    }
}

// MARK: - legend

private struct SkyDomeLegend: View {
    let sats: [SimSat]
    var body: some View {
        let present = Array(Set(sats.map(\.constellation))).sorted()
        FlowLayoutRow(items: present) { name in
            HStack(spacing: 4) {
                Circle().fill(SimSat.color(for: name)).frame(width: 10, height: 10)
                Text(name).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Minimal wrapping row for the legend chips (avoids depending on iOS 16 `Layout`).
private struct FlowLayoutRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.self) { content($0) }
            Spacer(minLength: 0)
        }
    }
}

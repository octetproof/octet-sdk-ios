import SwiftUI

/// A single simulated satellite for the GNSS · Sky screen. iOS doesn't expose
/// per-satellite GNSS, so these are our own representative values (see
/// `representativeSky`) — never live device data.
struct SimSat: Identifiable {
    let id = UUID()
    let constellation: String
    let svid: Int
    let band: String
    let azimuthDeg: Double
    let elevationDeg: Double
    let cn0: Double
    let usedInFix: Bool
    let hasEphemeris: Bool
    let hasAlmanac: Bool

    /// Short label, e.g. "G12" (GPS), "E07" (Galileo). Matches the Android table.
    var label: String { "\(SimSat.prefix(for: constellation))\(String(format: "%02d", svid))" }
    var color: Color { SimSat.color(for: constellation) }

    // Colours per constellation — shared by the dome and its legend (mirrors the
    // Android `constellationColors`).
    static func color(for constellation: String) -> Color {
        switch constellation {
        case "GPS": return Color(red: 0.31, green: 0.62, blue: 1.0)     // #4F9DFF
        case "GLONASS": return Color(red: 1.0, green: 0.42, blue: 0.42) // #FF6B6B
        case "Galileo": return Color(red: 0.22, green: 0.78, blue: 0.44)// #37C871
        case "BeiDou": return Color(red: 1.0, green: 0.64, blue: 0.23)  // #FFA23A
        case "QZSS": return Color(red: 0.69, green: 0.48, blue: 1.0)    // #B07BFF
        default: return Color(red: 0.60, green: 0.63, blue: 0.65)
        }
    }

    static func prefix(for constellation: String) -> String {
        switch constellation {
        case "GPS": return "G"
        case "GLONASS": return "R"
        case "Galileo": return "E"
        case "BeiDou": return "C"
        case "QZSS": return "J"
        default: return "S"
        }
    }

    /// A representative, healthy multi-constellation sky. Deterministic (seeded) so
    /// the picture is stable across opens and screenshots — it's an illustration,
    /// not a live reading.
    static func representativeSky() -> [SimSat] {
        var rng = SplitMix64(seed: 0x0C7E_7900_5A7E_11FE)
        // (constellation, band, svid range, how many to place)
        let plan: [(String, String, ClosedRange<Int>, Int)] = [
            ("GPS", "L1 C/A", 1...32, 5),
            ("Galileo", "E1", 1...36, 3),
            ("GLONASS", "L1 OF", 1...24, 3),
            ("BeiDou", "B1I", 6...46, 2),
            ("QZSS", "L1 C/A", 193...199, 1),
        ]
        var out: [SimSat] = []
        var usedSvids = Set<String>()
        for (name, band, svidRange, count) in plan {
            for _ in 0..<count {
                var svid = Int.random(in: svidRange, using: &rng)
                var guardN = 0
                while usedSvids.contains("\(name)\(svid)") && guardN < 20 {
                    svid = Int.random(in: svidRange, using: &rng); guardN += 1
                }
                usedSvids.insert("\(name)\(svid)")

                let az = Double.random(in: 0..<360, using: &rng)
                // Bias elevation toward mid-sky (few right on the horizon).
                let e = Double.random(in: 0...1, using: &rng)
                let el = 8 + (1 - e * e) * 78            // ~8°…86°, skewed high
                // Higher satellites tend to carry a cleaner signal.
                let base = 24 + (el / 86) * 20
                let cn0 = (base + Double.random(in: -4...5, using: &rng)).rounded()
                let used = el > 15 && cn0 > 30
                let eph = used || Double.random(in: 0...1, using: &rng) > 0.4
                out.append(SimSat(
                    constellation: name, svid: svid, band: band,
                    azimuthDeg: az, elevationDeg: el.rounded(), cn0: cn0,
                    usedInFix: used, hasEphemeris: eph,
                    hasAlmanac: eph || Double.random(in: 0...1, using: &rng) > 0.25
                ))
            }
        }
        return out
    }
}

/// A small deterministic PRNG (SplitMix64) so the simulated sky is reproducible
/// without relying on the platform RNG.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A 2.5D perspective "sky dome": each satellite is placed by azimuth (compass
/// bearing) and elevation (angle above the horizon) on a tilted hemisphere seen
/// from slightly above. Overhead (zenith) rises to the top; the horizon is the
/// tilted ellipse at the base. North is at the back, South at the front. Dot
/// colour = constellation, dot size = signal (C/N₀), filled = used in the fix.
/// Mirrors the Android `SkyDome` Canvas.
struct SkyDomeCanvas: View {
    let sats: [SimSat]
    var onSelect: (SimSat) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let g = DomeGeometry(w: w, h: h)
            ZStack {
                Canvas { ctx, _ in draw(&ctx, g) }
                // Tap targets over each satellite (Canvas isn't hit-testable per dot).
                ForEach(sats) { s in
                    let p = g.project(s.azimuthDeg, s.elevationDeg)
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                        .position(p)
                        .onTapGesture { onSelect(s) }
                }
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ g: DomeGeometry) {
        let grid = Color(red: 0.35, green: 0.38, blue: 0.41)

        // Elevation rings: horizon (0°) + 30° + 60°.
        for el in [0.0, 30.0, 60.0] {
            let cosEl = cos(el * .pi / 180)
            let ringRx = g.rx * cosEl, ringRy = g.ry * cosEl
            let ringCy = g.cy - g.domeH * sin(el * .pi / 180)
            let rect = CGRect(x: g.cx - ringRx, y: ringCy - ringRy, width: ringRx * 2, height: ringRy * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(grid.opacity(el == 0 ? 0.9 : 0.4)),
                       lineWidth: el == 0 ? 2.5 : 1.2)
        }

        // Azimuth spokes to the four cardinals + a zenith cross.
        let zenith = g.project(0, 90)
        for az in [0.0, 90.0, 180.0, 270.0] {
            var p = Path(); p.move(to: zenith); p.addLine(to: g.project(az, 0))
            ctx.stroke(p, with: .color(grid.opacity(0.35)), lineWidth: 1)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: zenith.x - 7, y: zenith.y)); cross.addLine(to: CGPoint(x: zenith.x + 7, y: zenith.y))
        cross.move(to: CGPoint(x: zenith.x, y: zenith.y - 7)); cross.addLine(to: CGPoint(x: zenith.x, y: zenith.y + 7))
        ctx.stroke(cross, with: .color(grid), lineWidth: 1.5)

        // Cardinal labels at the horizon.
        func label(_ t: String, _ az: Double, dy: CGFloat) {
            let p = g.project(az, 0)
            ctx.draw(Text(t).font(.system(size: 11)).foregroundColor(grid),
                     at: CGPoint(x: p.x, y: p.y + dy))
        }
        label("N", 0, dy: -8); label("S", 180, dy: 12); label("E", 90, dy: 4); label("W", 270, dy: 4)

        // Satellites (draw high-elevation last so they sit on top).
        for s in sats.sorted(by: { $0.elevationDeg < $1.elevationDeg }) {
            let p = g.project(s.azimuthDeg, s.elevationDeg)
            let r = 3 + (min(max(s.cn0, 0), 50) / 50) * 6
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            if s.usedInFix {
                ctx.fill(Path(ellipseIn: rect), with: .color(s.color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1.2)
            } else {
                ctx.stroke(Path(ellipseIn: rect), with: .color(s.color.opacity(0.55)), lineWidth: 1.6)
            }
        }

        // The observer — a red X at the centre of the horizon.
        let red = Theme.fail
        let s: CGFloat = 8
        var x = Path()
        x.move(to: CGPoint(x: g.cx - s, y: g.cy - s)); x.addLine(to: CGPoint(x: g.cx + s, y: g.cy + s))
        x.move(to: CGPoint(x: g.cx - s, y: g.cy + s)); x.addLine(to: CGPoint(x: g.cx + s, y: g.cy - s))
        ctx.stroke(x, with: .color(red), lineWidth: 3)
        ctx.draw(Text("you").font(.system(size: 10)).foregroundColor(red),
                 at: CGPoint(x: g.cx, y: g.cy + 22))
    }
}

/// Shared dome projection geometry — one source of truth for the Canvas drawing
/// and the tap-target overlay.
private struct DomeGeometry {
    let cx, cy, rx, ry, domeH: CGFloat
    init(w: CGFloat, h: CGFloat) {
        cx = w / 2
        cy = h * 0.60
        rx = min(w * 0.42, h * 0.72)
        ry = min(w * 0.42, h * 0.72) * 0.42
        domeH = min(w * 0.42, h * 0.72) * 0.58
    }
    func project(_ azDeg: Double, _ elDeg: Double) -> CGPoint {
        let a = azDeg * .pi / 180
        let el = min(max(elDeg, 0), 90)
        let elR = el * .pi / 180
        let gg = CGFloat(cos(elR)) // 1 at horizon, 0 at zenith
        let x = cx + rx * gg * CGFloat(sin(a))
        let y = cy - ry * gg * CGFloat(cos(a)) - domeH * CGFloat(sin(elR))
        return CGPoint(x: x, y: y)
    }
}

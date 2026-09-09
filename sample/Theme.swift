import SwiftUI
import UIKit

// Visual language for the sample — a small, deliberate token set so every
// screen speaks the same palette / type / iconography. Native-clean, Octet-
// branded through one accent + the verdict colours; theme-aware (the neutrals
// come from the system so light/dark both look right).

enum Theme {
    /// The single Octet accent — a "signal" cyan. Used sparingly: the active
    /// pipeline step, the primary CTA, links. Works on both grounds.
    static let accent = Color(red: 0.02, green: 0.66, blue: 0.78)

    // Semantic verdict colours — kept separate from the accent so "good/warn/bad"
    // never reads as "branded".
    static let pass = Color(red: 0.09, green: 0.64, blue: 0.29)   // #16A34A
    static let warn = Color(red: 0.85, green: 0.47, blue: 0.02)   // #D97706
    static let fail = Color(red: 0.86, green: 0.15, blue: 0.15)   // #DC2626
    static let neutral = Color.secondary

    /// Monospaced face for proof bytes, hashes, timings, the debug log.
    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Consistent spacing scale.
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24 }
}

/// The status vocabulary used everywhere (pipeline steps, check rows, verdicts).
/// Keeping one enum means ✓ / ● / ○ / ⚠ / ⃝ always mean the same thing.
enum StatusKind {
    case ok, active, pending, warn, notChecked, bad

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .active: return "circle.fill"
        case .pending: return "circle"
        case .warn: return "exclamationmark.triangle.fill"
        case .notChecked: return "minus.circle"
        case .bad: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: return Theme.pass
        case .active: return Theme.accent
        case .pending: return Theme.neutral.opacity(0.5)
        case .warn: return Theme.warn
        case .notChecked: return Theme.neutral
        case .bad: return Theme.fail
        }
    }
}

/// A small status glyph — one line so every list/row is consistent.
struct StatusDot: View {
    let kind: StatusKind
    var body: some View {
        Image(systemName: kind.symbol)
            .foregroundStyle(kind.color)
            .imageScale(.medium)
            .accessibilityHidden(true)
    }
}

/// A compact rounded label (confidence bucket, "fresh", "imported", tags).
struct Chip: View {
    let text: String
    var tint: Color = Theme.neutral
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Section card wrapper — the framed panels on Generate/Verify.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

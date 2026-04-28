import SwiftUI

/// Centralized design tokens for the Onpa app. Keeps custom chrome consistent and
/// makes it easy to evolve toward the system's Liquid Glass-era styling without a
/// search-and-replace each time. Always prefer system materials, system colors,
/// and SF Symbols over hand-rolled chrome; this namespace exists for the cases
/// where SwiftUI's stock containers do not fit.
enum DS {
    /// Brand accent color used across primary actions, icons, and emphasis chips.
    /// Backed by the asset catalog when present, otherwise the system teal so the
    /// app still adopts the platform palette automatically.
    static var accent: Color { .teal }

    /// Surface backgrounds layered on top of `Color(.systemGroupedBackground)` to
    /// match the standard iOS grouped style. Keep these aligned with whatever
    /// system tone Apple ships in future releases.
    enum Surface {
        static var grouped: Color { Color(.systemGroupedBackground) }
        static var card: Color { Color(.secondarySystemGroupedBackground) }
        static var inset: Color { Color(.tertiarySystemGroupedBackground) }
    }

    /// Standard corner radii. Prefer the smallest radius that still reads as a
    /// "card" so views feel consistent with system controls.
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xlarge: CGFloat = 14
    }

    /// Common shapes derived from the radius scale.
    enum Shape {
        static var card: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.medium, style: .continuous) }
        static var inset: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.small, style: .continuous) }
        static var large: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.large, style: .continuous) }
        static var xlarge: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.xlarge, style: .continuous) }
    }

    /// Translucent overlays for floating elements (image credit chips, etc.). Use
    /// system materials wherever possible instead of these.
    enum Overlay {
        static var darkChip: Color { .black.opacity(0.62) }
    }

    /// Tints derived from the brand accent. Use sparingly; system colors should
    /// be preferred when the meaning is generic.
    enum AccentTint {
        static var soft: Color { Color.teal.opacity(0.12) }
        static var medium: Color { Color.teal.opacity(0.18) }
        static var strong: Color { Color.teal.opacity(0.25) }
    }
}

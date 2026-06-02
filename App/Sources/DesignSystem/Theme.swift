import SwiftUI

/// Nautilarr's nautical-themed design tokens. Brand colours mirror the app icon
/// (deep navy → teal). All original artwork and palette.
enum Theme {
    static let navy = Color("BrandNavy")
    static let teal = Color("BrandTeal")

    /// Background gradient used behind hero/dashboard surfaces.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [navy, navy.opacity(0.85), teal.opacity(0.35)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    enum Metrics {
        static let cornerRadius: CGFloat = 14
        static let posterAspect: CGFloat = 2.0 / 3.0
        static let cardPadding: CGFloat = 14
    }
}

extension Color {
    /// iOS 16-compatible system colours (UIKit-backed; valid on Mac Catalyst).
    static var cardBackground: Color { Color(uiColor: .secondarySystemBackground) }
    static var hairline: Color { Color(uiColor: .separator) }

    /// Builds a colour from a 24-bit `0xRRGGBB` hex value.
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// User-selectable accent colours. The default is the brand teal.
enum AccentPalette: String, CaseIterable, Identifiable, Codable {
    case teal, blue, indigo, purple, pink, red, orange, green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .teal: return Theme.teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        }
    }

    var label: String { rawValue.capitalized }
}

/// User-selectable **background tint** for the whole app. Pastel washes derived
/// from the same hue family as the accent colours — `.system` keeps the plain
/// system background. The tint sits behind every screen so the Liquid Glass
/// surfaces pick it up.
enum BackgroundPalette: String, CaseIterable, Identifiable, Codable {
    case system, teal, blue, indigo, purple, pink, rose, peach, mint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .rose: return "Rose"
        case .peach: return "Peach"
        case .mint: return "Mint"
        }
    }

    /// The pastel hue used for the wash. `nil` for `.system`.
    var pastel: Color? {
        switch self {
        case .system: return nil
        case .teal:   return Color(red: 0.55, green: 0.86, blue: 0.83)
        case .blue:   return Color(red: 0.66, green: 0.82, blue: 0.98)
        case .indigo: return Color(red: 0.71, green: 0.74, blue: 0.97)
        case .purple: return Color(red: 0.82, green: 0.73, blue: 0.96)
        case .pink:   return Color(red: 0.98, green: 0.76, blue: 0.88)
        case .rose:   return Color(red: 0.98, green: 0.74, blue: 0.74)
        case .peach:  return Color(red: 0.99, green: 0.83, blue: 0.69)
        case .mint:   return Color(red: 0.70, green: 0.92, blue: 0.78)
        }
    }

    /// Whether a custom (non-system) wash is active.
    var isCustom: Bool { pastel != nil }

    /// A `ShapeStyle` for the wash, used as a `containerBackground` on the
    /// navigation stack so it shows behind *every* screen (root and pushed) —
    /// drawn over the system background, so it adapts to light/dark. `nil` for
    /// `.system`.
    var containerStyle: AnyShapeStyle? {
        guard let pastel else { return nil }
        return AnyShapeStyle(
            LinearGradient(
                colors: [pastel.opacity(0.62), pastel.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// A full-bleed background that adapts to light/dark: the system background
    /// (so text contrast is preserved) with the pastel hue layered on top. The
    /// tint is deliberately strong enough to read clearly as a colour (grouped
    /// "cards" stay legible on top), unlike the old near-invisible wash.
    @ViewBuilder
    var backgroundView: some View {
        if let pastel {
            PastelBackground(pastel: pastel)
        } else {
            Color.clear
        }
    }
}

/// The pastel wash, adapting its strength to light/dark so the colour is clearly
/// visible in light mode without washing out text in dark mode.
private struct PastelBackground: View {
    let pastel: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = scheme == .dark ? 0.50 : 0.85
        let bottom = scheme == .dark ? 0.26 : 0.55
        ZStack {
            Rectangle().fill(Color(uiColor: .systemBackground))
            LinearGradient(
                colors: [pastel.opacity(top), pastel.opacity(bottom)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Tints the screen with the selected pastel background (no-op for `.system`)
    /// and makes its scrollable container transparent so the wash shows through.
    ///
    /// Takes the palette as a parameter (rather than reading it from the
    /// environment inside a `ViewModifier`) so it updates **live**: the caller is
    /// a `View` that already re-renders when `AppSettings` publishes, whereas a
    /// `ViewModifier` reading `@EnvironmentObject` could lag a navigation cycle.
    @ViewBuilder
    func appBackground(_ palette: BackgroundPalette) -> some View {
        self
            .scrollContentBackground(palette.isCustom ? .hidden : .automatic)
            .background(palette.backgroundView)
    }

    /// Sets the pastel wash as the **navigation container's** background so it is
    /// visible behind every screen — including pushed views — on iPhone, where a
    /// plain `.background()` behind the `NavigationStack` is hidden by the
    /// navigation controller's own opaque background. Apply to the root content
    /// *inside* a `NavigationStack` (paired with `scrollContentBackground(.hidden)`
    /// on the stack so the lists are transparent).
    @ViewBuilder
    func navigationWash(_ palette: BackgroundPalette) -> some View {
        if let style = palette.containerStyle {
            if #available(iOS 18.0, macCatalyst 18.0, *) {
                self.containerBackground(style, for: .navigation)
            } else {
                self.background(palette.backgroundView)
            }
        } else {
            self
        }
    }
}

/// User-selectable appearance.
enum AppColorScheme: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var swiftUIScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

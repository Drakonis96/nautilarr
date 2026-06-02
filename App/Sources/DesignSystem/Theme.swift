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

    /// Light-mode RGB of the hue. `nil` for `.system`. Single source of truth for
    /// both the settings swatch and the live background colour.
    private var rgb: (red: Double, green: Double, blue: Double)? {
        switch self {
        case .system: return nil
        case .teal:   return (0.55, 0.86, 0.83)
        case .blue:   return (0.66, 0.82, 0.98)
        case .indigo: return (0.71, 0.74, 0.97)
        case .purple: return (0.82, 0.73, 0.96)
        case .pink:   return (0.98, 0.76, 0.88)
        case .rose:   return (0.98, 0.74, 0.74)
        case .peach:  return (0.99, 0.83, 0.69)
        case .mint:   return (0.70, 0.92, 0.78)
        }
    }

    /// The hue as a plain colour (used for the settings swatch preview).
    var pastel: Color? {
        guard let rgb else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Whether a custom (non-system) colour is active.
    var isCustom: Bool { rgb != nil }

    /// A **solid**, scheme-adaptive background colour. It plays the exact role
    /// the grey `systemGroupedBackground` plays for `.system`: a flat fill behind
    /// the screen, with the grouped "cards" staying white on top. The tint is
    /// kept deliberately **soft** — a gentle wash like the system grey, not a
    /// saturated colour — so the white cards still read clearly. In light mode
    /// it's a pale tint of the hue; in dark mode it's a deep, muted version.
    /// `nil` for `.system`.
    var solidColor: Color? {
        guard let rgb else { return nil }
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                // Blend the hue toward near-black so the background reads as a
                // softly-tinted dark surface (cards stay legible on top).
                let t = 0.86, base = 0.05
                return UIColor(red: rgb.red * (1 - t) + base * t,
                               green: rgb.green * (1 - t) + base * t,
                               blue: rgb.blue * (1 - t) + base * t, alpha: 1)
            }
            // Blend the hue toward near-white so it's a soft, subtle tint
            // (mirroring how the system grouped grey is barely-there).
            let t = 0.60, base = 0.98
            return UIColor(red: rgb.red * (1 - t) + base * t,
                           green: rgb.green * (1 - t) + base * t,
                           blue: rgb.blue * (1 - t) + base * t, alpha: 1)
        })
    }

    /// The card ("globo") colour shown on top of the tinted background. Rather
    /// than near-white (which read as ugly white blobs on a soft tint), the card
    /// carries a **clearly visible tint** of the same hue — a colour panel a bit
    /// more saturated than the background, so the whole screen reads as one
    /// cohesive monochrome palette. The rounded grouped-list shape + separators
    /// keep the cards distinct. In dark mode it's a tinted dark surface, kept
    /// lighter than the background so cards lift. `nil` for `.system`.
    var cardColor: Color? {
        guard let rgb else { return nil }
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                let t = 0.74, base = 0.16
                return UIColor(red: rgb.red * (1 - t) + base * t,
                               green: rgb.green * (1 - t) + base * t,
                               blue: rgb.blue * (1 - t) + base * t, alpha: 1)
            }
            let t = 0.32, base = 1.0
            return UIColor(red: rgb.red * (1 - t) + base * t,
                           green: rgb.green * (1 - t) + base * t,
                           blue: rgb.blue * (1 - t) + base * t, alpha: 1)
        })
    }

    /// A full-bleed solid background that replaces the grey grouped background
    /// with the selected colour. `.system` keeps the plain (transparent) one.
    @ViewBuilder
    var backgroundView: some View {
        if let solidColor {
            solidColor.ignoresSafeArea()
        } else {
            Color.clear
        }
    }
}

extension View {
    /// Tints a screen's background with the selected colour (no-op for `.system`)
    /// while keeping the grouped "cards" white — exactly like the grey `.system`
    /// default, but in the chosen hue.
    ///
    /// Applied to the **root content of each screen** (including pushed views, in
    /// a cascade), so the tint shows uniformly regardless of whether the screen is
    /// a `List`/`Form`, a `ScrollView` or a plain stack: `.background()` paints the
    /// tint directly behind the content, and `scrollContentBackground(.hidden)`
    /// makes any scrollable container transparent so the tint shows through while
    /// the cells keep their own (white) background.
    ///
    /// Takes the palette as a parameter (rather than reading it from the
    /// environment inside a `ViewModifier`) so it updates **live**: the caller is
    /// a `View` that already re-renders when `AppSettings` publishes.
    @ViewBuilder
    func appBackground(_ palette: BackgroundPalette) -> some View {
        if palette.isCustom {
            self
                .scrollContentBackground(.hidden)
                // Force the content to fill the screen so the tint covers the
                // whole background — otherwise `.background()` only spans the
                // content's own bounds (e.g. a small centred empty-state view),
                // leaving the rest of the screen its default colour.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.backgroundView)
        } else {
            self
        }
    }

    /// Forces the tab bar and navigation bar to use the tinted background colour
    /// *consistently*, instead of iOS's default of flipping between an opaque
    /// material (when content scrolls under the bar) and a transparent edge
    /// appearance (showing the tint only at the scroll edge). Without this the
    /// bottom tab bar looks white while scrolling and tinted at the bottom.
    /// No-op for `.system`.
    @ViewBuilder
    func themedBars(_ palette: BackgroundPalette) -> some View {
        if let color = palette.solidColor {
            // Only the tab bar is forced to the tint; the navigation bar keeps its
            // default behaviour (transparent at the scroll edge) so there's no
            // hairline separator under the large title — letting the Home ocean
            // meet the title seamlessly.
            self
                .toolbarBackground(color, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        } else {
            self
        }
    }
}

// MARK: - Card ("globo") tint

/// The soft card colour to apply to grouped list rows, injected at the app root
/// from the chosen `BackgroundPalette` and read by `.tintedCards()`. `nil` keeps
/// the default system card colour (`.system` background).
private struct CardTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var cardTint: Color? {
        get { self[CardTintKey.self] }
        set { self[CardTintKey.self] = newValue }
    }
}

private struct TintedCardsModifier: ViewModifier {
    @Environment(\.cardTint) private var tint
    func body(content: Content) -> some View {
        content.listRowBackground(tint)
    }
}

extension View {
    /// Tints grouped list rows ("cards") with the app's soft card colour (read
    /// from the environment, injected at the app root from the chosen palette),
    /// so the cards harmonise with the tinted background instead of reading as
    /// hard white blobs. Apply to a `List`/`Form`; it propagates to every row.
    /// A `nil` tint (the `.system` background) keeps the default card colour.
    func tintedCards() -> some View {
        modifier(TintedCardsModifier())
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

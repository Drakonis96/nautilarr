import SwiftUI

extension View {
    /// Applies Apple's **Liquid Glass** material (iOS / macOS 26+) to a surface,
    /// falling back to the app's translucent material card style on earlier OS
    /// versions. Use for cards, pills and floating surfaces so Nautilarr looks
    /// native on the latest OS while still running on iOS 17+.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(in shape: S, tinted: Bool = false) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
            self.glassEffect(tinted ? .regular.tint(Theme.teal.opacity(0.25)) : .regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.hairline.opacity(0.4)))
        }
    }

    /// Glass treatment for small interactive chips/pills (capsule shape).
    @ViewBuilder
    func glassChip() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Glass treatment for circular icon buttons.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.hairline.opacity(0.4)))
        }
    }
}

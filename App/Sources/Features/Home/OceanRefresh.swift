import SwiftUI

/// Scroll-offset preference used by the Home dashboard's custom pull-to-refresh
/// (fallback path for iOS < 18; iOS 18+ uses `onScrollGeometryChange`).
struct HomePullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The Nautilarr submarine sailing on a living swell — the resting mark at the
/// top of Home and the pull-to-refresh indicator. The sea is always gently
/// moving; pulling whips it up and grows the sub, and on release the sub bounces
/// on the waves while the dashboard reloads (instead of the system spinner).
struct OceanRefreshIndicator: View {
    /// 0 at rest → ~1.3 once pulled well past the refresh threshold.
    var progress: CGFloat
    var refreshing: Bool
    /// Waves and the submarine are tinted with the app's accent colour.
    var accent: Color = Theme.teal

    var body: some View {
        // Always animating so the swell drifts subtly the whole time.
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            // Calm at rest, choppier as you pull, full storm while refreshing.
            let turbulence = refreshing ? 1.0 : 0.22 + Double(min(1, progress)) * 0.78
            ZStack(alignment: .bottom) {
                WaterLayer(t: t, turbulence: turbulence, layer: 0).fill(accent.opacity(0.18))
                WaterLayer(t: t, turbulence: turbulence, layer: 1).fill(accent.opacity(0.32))
                submarine(t: t)
                WaterLayer(t: t, turbulence: turbulence, layer: 2).fill(accent.opacity(0.45))
            }
            // No top clip: let the sub grow and bounce above the frame without
            // being cut off when you pull down.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func submarine(t: Double) -> some View {
        let p = Double(min(1.2, progress))
        let pullScale = 1.0 + p * 0.35
        // While refreshing: a lively bounce on the swell — the sub springs up off
        // the water and drops back, over and over, until the reload finishes.
        // `|sin|` gives true bounce arcs (fast at the water, slow at the apex).
        let bouncePhase = refreshing ? abs(sin(t * 2.1)) : 0   // 0 = on the water, 1 = apex
        let bob: Double = refreshing ? -bouncePhase * 34 : 3.2 * sin(t * 1.5)
        // A touch of squash-and-stretch on contact for a springy feel.
        let squash = refreshing ? 1.0 - (1.0 - bouncePhase) * 0.13 : 1.0
        let tilt = (refreshing ? 7.0 : 3.5) * sin(t * (refreshing ? 2.1 : 1.0)) + p * 8
        return Image("AppLogo")              // original colours — only the waves take the accent
            .resizable()
            .scaledToFit()
            .frame(width: 104, height: 104)
            .scaleEffect(x: pullScale / squash, y: pullScale * squash, anchor: .bottom)
            .rotationEffect(.degrees(tilt))
            .offset(y: -8 + bob)
            .shadow(color: Theme.navy.opacity(0.4), radius: 10, y: 6)
    }
}

/// One organic water layer: several sine waves of different frequency, phase and
/// amplitude superposed so the surface never looks like a single repeating sine.
private struct WaterLayer: Shape {
    var t: Double
    var turbulence: Double
    var layer: Int

    func path(in rect: CGRect) -> Path {
        let amp = (2.5 + turbulence * 15.0) * (1.0 + Double(layer) * 0.25)
        let baseline = rect.height * (0.40 + Double(layer) * 0.16)
        let phase = t * (0.9 + Double(layer) * 0.4) + Double(layer) * 2.3
        let w = max(Double(rect.width), 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))
        var x: CGFloat = 0
        while x <= rect.width {
            let rel = Double(x) / w
            let y = baseline
                + sin(rel * 2 * .pi * (1.4 + Double(layer) * 0.5) + phase) * amp
                + sin(rel * 2 * .pi * 3.3 + phase * 1.6) * (amp * 0.35)
                + sin(rel * 2 * .pi * 0.6 - phase * 0.55) * (amp * 0.55)
            path.addLine(to: CGPoint(x: x, y: CGFloat(y)))
            x += 3
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

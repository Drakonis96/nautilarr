import SwiftUI

/// Scroll-offset preference used by the Home dashboard's custom pull-to-refresh
/// (fallback path for iOS < 18; iOS 18+ uses `onScrollGeometryChange`).
struct HomePullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The Nautilarr submarine, hanging from an anchor chain that drops **from the
/// Dynamic Island** at the very top of the screen. The chain is always visible.
/// The sea is calm and unaffected by the pull — only the sub (and the chain it
/// hangs from) move: dragging down lowers the sub into the deep, and on release
/// the chain hauls it back up *slowly* while the dashboard reloads.
///
/// Rendered as a top overlay that ignores the top safe area, so the chain's
/// origin tucks behind the Dynamic Island and reads as attached to it.
struct OceanHeader: View {
    /// Live dive depth from the drag (0 = at the surface, 1 = deepest).
    var dive: CGFloat = 0
    /// Set to "now" when the slow haul-up begins (on release); `nil` otherwise.
    var riseStart: Date? = nil
    /// Dive depth at the moment of release (the rise interpolates this → 0).
    var riseFrom: CGFloat = 0
    var refreshing: Bool = false
    var accent: Color = Theme.teal

    /// Comic speech-bubble easter egg: tap the captain to make him say his line.
    @State private var speaking = false
    @State private var speakTask: Task<Void, Never>?

    /// How long the chain takes to haul the sub back up — slow and gradual.
    private let riseDuration: Double = 2.6
    /// Where the chain leaves the Dynamic Island (screen-top coordinates).
    private let islandY: CGFloat = 6
    /// The calm sea's surface line (screen-top coordinates).
    private let surfaceY: CGFloat = 124
    /// How far down the sub travels at full dive.
    private let diveRange: CGFloat = 88

    /// Tappable strip height — the whole ocean band, so tapping anywhere in it
    /// (not just precisely on the sub) pops the captain's line.
    private var bandHeight: CGFloat { surfaceY + 96 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                // The animated ocean (waves + chain + sub). The tap gesture lives
                // OUTSIDE this TimelineView — it re-renders ~60fps and would keep
                // tearing down a gesture placed inside, dropping taps.
                TimelineView(.animation) { timeline in
                    let now = timeline.date
                    let t = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    // While rising, interpolate riseFrom → 0 over `riseDuration`
                    // using the timeline clock (TimelineView ignores withAnimation,
                    // so the rise must be time-driven to look smooth).
                    let depth: Double = {
                        if let riseStart {
                            let p = min(1, max(0, now.timeIntervalSince(riseStart) / riseDuration))
                            let eased = p * p * (3 - 2 * p)   // smoothstep — steady haul-up
                            return Double(riseFrom) * (1 - eased)
                        }
                        return Double(dive)
                    }()
                    let bob = depth > 0.03 ? 0 : 3.0 * sin(t * 1.5)
                    let subCenterY = surfaceY + 8 + CGFloat(depth) * diveRange + CGFloat(bob)
                    let chainLen = max(2, (subCenterY - 32) - islandY)
                    ZStack(alignment: .topLeading) {
                        AnchorChain()
                            .frame(width: 14, height: chainLen)
                            .position(x: w / 2, y: islandY + chainLen / 2)
                        submarine(t: t)
                            .position(x: w / 2, y: subCenterY)
                        // Calm sea drawn last so the sub sits half-submerged.
                        sea(t: t, width: w)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .allowsHitTesting(false)

                // Tap anywhere across the ocean band → the captain speaks.
                Color.clear
                    .frame(width: w, height: bandHeight)
                    .contentShape(Rectangle())
                    .position(x: w / 2, y: bandHeight / 2)
                    .onTapGesture { speak() }

                // The captain's line floats to his right (open water, at the
                // resting waterline — always clear of the title above).
                if speaking {
                    ComicBubble()
                        .position(x: w / 2 + 98, y: surfaceY - 12)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: speaking)
        }
    }

    /// Pop the captain's speech bubble, auto-hiding it after a moment.
    private func speak() {
        speaking = true
        speakTask?.cancel()
        speakTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            speaking = false
        }
    }

    /// The calm sea band: three superposed wave layers at a fixed surface line.
    private func sea(t: Double, width: CGFloat) -> some View {
        let bandHeight: CGFloat = 84
        return ZStack(alignment: .top) {
            WaterLayer(t: t, layer: 0).fill(accent.opacity(0.16))
            WaterLayer(t: t, layer: 1).fill(accent.opacity(0.30))
            WaterLayer(t: t, layer: 2).fill(accent.opacity(0.42))
        }
        .frame(width: width, height: bandHeight)
        // Position the band so its surface (top) sits at `surfaceY`.
        .offset(y: surfaceY)
    }

    private func submarine(t: Double) -> some View {
        // Hangs upright from the chain with a gentle sway; faces left (unmirrored).
        let tilt = 3.0 * sin(t * 1.0)
        return Image("AppLogo")              // original colours — only the waves take the accent
            .resizable()
            .scaledToFit()
            .frame(width: 104, height: 104)
            .rotationEffect(.degrees(tilt))
            .shadow(color: Theme.navy.opacity(0.4), radius: 10, y: 6)
    }
}

/// A comic speech bubble for the captain's easter-egg line (localized).
private struct ComicBubble: View {
    var body: some View {
        Text("Arr, sailor!")
            .font(.system(.footnote, design: .rounded).weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 13)
            .padding(.top, 7)
            .padding(.bottom, 16)              // room for the tail
            .background(SpeechBubble().fill(.white))
            .overlay(SpeechBubble().stroke(Color.black, lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .fixedSize()
    }
}

/// Rounded speech bubble with a downward tail (drawn as a single continuous path
/// so the outline is unbroken).
private struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let tailH: CGFloat = 10
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailH)
        var p = Path(roundedRect: body, cornerRadius: 12)
        // Tail near the bottom-left, tip angled down-left toward the captain.
        let tx = body.minX + 20
        var tail = Path()
        tail.move(to: CGPoint(x: tx + 8, y: body.maxY - 1))
        tail.addLine(to: CGPoint(x: tx - 10, y: rect.maxY))
        tail.addLine(to: CGPoint(x: tx - 4, y: body.maxY - 1))
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}

/// A short interlocking anchor chain: oval links alternating vertical/horizontal
/// and overlapping, so it reads as a real linked chain rather than a dashed line.
private struct AnchorChain: View {
    var body: some View {
        Canvas { ctx, size in
            let linkLong: CGFloat = 11
            let linkShort: CGFloat = 7
            let step = linkLong - 3.5          // overlap so links interlock
            let cx = size.width / 2
            let metal = Color(white: 0.55)
            var y: CGFloat = 0
            var i = 0
            while y < size.height {
                let vertical = (i % 2 == 0)
                let rect = vertical
                    ? CGRect(x: cx - linkShort / 2, y: y, width: linkShort, height: linkLong)
                    : CGRect(x: cx - linkLong / 2, y: y + (linkLong - linkShort) / 2,
                             width: linkLong, height: linkShort)
                ctx.stroke(Path(ellipseIn: rect), with: .color(metal), lineWidth: 2.2)
                y += step
                i += 1
            }
        }
    }
}

/// One organic water layer at a fixed (calm) amplitude: several sine waves of
/// different frequency/phase superposed so the surface never looks like a single
/// repeating sine. Fills downward from its surface line.
private struct WaterLayer: Shape {
    var t: Double
    var layer: Int

    func path(in rect: CGRect) -> Path {
        let amp = (2.5 + 0.25 * 9.0) * (1.0 + Double(layer) * 0.25)   // constant, calm
        let baseline = rect.height * (0.04 + Double(layer) * 0.10)
        // Negative drift → waves travel in the opposite direction to before.
        let phase = -t * (0.9 + Double(layer) * 0.4) + Double(layer) * 2.3
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

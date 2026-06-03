import SwiftUI

/// Scroll-offset preference used by the Home dashboard's custom pull-to-refresh
/// (fallback path for iOS < 18; iOS 18+ uses `onScrollGeometryChange`).
struct HomePullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The Nautilarr submarine, hanging from an anchor chain that drops **from the
/// Dynamic Island** at the very top of the screen. The chain is always visible.
/// Only the sub (and the chain it hangs from) move: dragging down lowers the sub
/// into the deep, and on release the chain hauls it back up *slowly* while the
/// dashboard reloads. Tapping the captain pops a comic speech bubble.
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

    /// Comic speech-bubble easter egg: tap the captain to make him say a line.
    /// Lines are picked at random (avoiding an immediate repeat) on each tap.
    @State private var speaking = false
    @State private var speakTask: Task<Void, Never>?
    @State private var message: LocalizedStringKey = "Arr, sailor!"

    /// Localized one-liners the captain says, cycled randomly. These reuse the
    /// existing easter-egg catalog keys.
    private let messages: [LocalizedStringKey] = [
        "Arr, sailor!",
        "Can you stop, please?",
        "Arrr… stop now.",
        "That won't help, will it?",
        "Seriously, quit poking me!",
        "I'm trying to sail here.",
        "You again? Really?"
    ]

    /// How long the chain takes to haul the sub back up — slow and gradual.
    private let riseDuration: Double = 2.6
    /// Where the chain leaves the Dynamic Island (screen-top coordinates).
    private let islandY: CGFloat = 6
    /// The submarine's resting waterline (screen-top coordinates).
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
                // The animated chain + submarine. The tap gesture lives OUTSIDE
                // this TimelineView — it re-renders ~60fps and would keep tearing
                // down a gesture placed inside, dropping taps.
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
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .allowsHitTesting(false)

                // Tap ONLY the submarine → the captain speaks. Laid out with
                // alignment + offset (NOT `.position`, whose hit area behaved
                // unreliably here) and kept OUTSIDE the TimelineView so the
                // gesture isn't torn down every frame.
                Color.clear
                    .frame(width: 168, height: 150)
                    .contentShape(Rectangle())
                    .onTapGesture { speak() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .offset(y: surfaceY + 8 - 75)

                // The captain's line pops out of the porthole: up and to his
                // right, its tail aimed back down-left at the captain. Scaling
                // from the tail (.bottomLeading) makes it look like it emerges
                // FROM him, not slide up from below.
                if speaking {
                    ComicBubble(message: message)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(x: 92, y: surfaceY - 34)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.35, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: speaking)
        }
    }

    /// Pop the captain's speech bubble with a fresh random line, auto-hiding it
    /// after a moment.
    private func speak() {
        if messages.count > 1 {
            var next = message
            while next == message { next = messages.randomElement() ?? message }
            message = next
        }
        speaking = true
        speakTask?.cancel()
        speakTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            speaking = false
        }
    }

    private func submarine(t: Double) -> some View {
        // Hangs upright from the chain with a gentle sway; faces left (unmirrored).
        let tilt = 3.0 * sin(t * 1.0)
        return Image("AppLogo")              // original colours
            .resizable()
            .scaledToFit()
            .frame(width: 104, height: 104)
            .rotationEffect(.degrees(tilt))
            .shadow(color: Theme.navy.opacity(0.4), radius: 10, y: 6)
    }
}

/// A comic speech bubble for the captain's easter-egg line (localized).
private struct ComicBubble: View {
    var message: LocalizedStringKey = "Arr, sailor!"
    var body: some View {
        Text(message)
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


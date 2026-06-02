import SwiftUI
import NautilarrCore

/// A playful easter egg: tapping a service icon on the dashboard makes it leap
/// out of its card and bounce a little higher with every tap, splashing as it
/// goes, until it reaches the top — then it nosedives back down and the
/// Nautilarr submarine pops up a comic speech bubble begging you to stop (in the
/// user's language). Purely cosmetic; it never blocks the UI.
@MainActor
final class ServicePrankController: ObservableObject {
    struct Flyer: Equatable {
        let type: ServiceType
        var hops: Int
    }

    @Published private(set) var flyer: Flyer?
    @Published private(set) var diving = false
    @Published private(set) var bubble: LocalizedStringKey?
    /// Bumped on every tap so the splash effect re-triggers.
    @Published private(set) var splashTick = 0

    /// Taps needed to climb from the card to the top of the screen.
    let maxHops = 7

    private var messageIndex = 0
    private var generation = 0

    /// The nag messages, cycled on each climax. Localized via the `.lproj`
    /// catalogs (English keys are the base strings).
    private let messages: [LocalizedStringKey] = [
        "Can you stop, please?",
        "Arrr… stop now.",
        "That won't help, will it?",
        "Seriously, quit poking me!",
        "I'm trying to sail here.",
        "You again? Really?"
    ]

    /// Registers a tap on a service icon.
    func bump(_ type: ServiceType) {
        // Tapping a different service restarts the climb with that icon.
        if flyer?.type != type {
            generation += 1
            flyer = Flyer(type: type, hops: 0)
            diving = false
            bubble = nil
        }
        guard var current = flyer, !diving else { return }
        current.hops += 1
        flyer = current
        splashTick += 1
        if current.hops >= maxHops { climax() }
    }

    /// Fraction of the way to the top (0 = resting on the card, 1 = at the top).
    func progress(for flyer: Flyer) -> Double {
        min(1, Double(flyer.hops) / Double(maxHops))
    }

    private func climax() {
        diving = true
        bubble = messages[messageIndex % messages.count]
        messageIndex += 1
        let token = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            // Only clear if no fresh prank started in the meantime.
            guard token == self.generation else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                self.flyer = nil
                self.diving = false
                self.bubble = nil
            }
        }
    }
}

// MARK: - Overlay

/// Full-screen, non-interactive overlay that animates the flying icon, splashes,
/// the diving climax and the submarine's speech bubble.
struct ServicePrankOverlay: View {
    @ObservedObject var controller: ServicePrankController

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let flyer = controller.flyer {
                    let pos = iconPosition(flyer, size: geo.size)

                    SplashView()
                        .id(controller.splashTick)
                        .position(x: pos.x, y: pos.y + 24)

                    flyingIcon(flyer.type)
                        .position(pos)
                        .animation(animation, value: pos)
                        .animation(animation, value: controller.diving)

                    if let bubble = controller.bubble {
                        submarine(message: bubble, size: geo.size)
                            .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var animation: Animation {
        controller.diving
            ? .interpolatingSpring(stiffness: 130, damping: 11)
            : .spring(response: 0.34, dampingFraction: 0.52)
    }

    private func iconPosition(_ flyer: ServicePrankController.Flyer, size: CGSize) -> CGPoint {
        let w = size.width, h = size.height
        if controller.diving {
            // Nosedive down onto the submarine at the bottom.
            return CGPoint(x: w * 0.5, y: h * 0.78)
        }
        let p = controller.progress(for: flyer)
        let y = h * (0.70 - 0.58 * p)                  // climbs from ~70% up to ~12%
        let sway = sin(Double(flyer.hops) * 1.5) * Double(w) * 0.11
        return CGPoint(x: w * 0.5 + sway, y: y)
    }

    private func flyingIcon(_ type: ServiceType) -> some View {
        ServiceIcon(type: type, size: 40)
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.35)))
            .shadow(color: .black.opacity(0.35), radius: 7, y: 4)
            .rotationEffect(.degrees(controller.diving ? 540 : 0))
    }

    private func submarine(message: LocalizedStringKey, size: CGSize) -> some View {
        VStack(spacing: 4) {
            ComicBubble(message: message)
                .frame(maxWidth: size.width * 0.7)
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .shadow(color: Theme.navy.opacity(0.5), radius: 10, y: 6)
        }
        .position(x: size.width * 0.5, y: size.height * 0.84)
    }
}

// MARK: - Splash

private struct SplashView: View {
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let angle = Double(i) / 7 * .pi * 2
                Circle()
                    .fill(Theme.teal.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .offset(
                        x: go ? CGFloat(cos(angle)) * 34 : 0,
                        y: go ? CGFloat(sin(angle)) * 18 + 14 : 0
                    )
                    .opacity(go ? 0 : 0.9)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { go = true } }
    }
}

// MARK: - Comic speech bubble

private struct ComicBubble: View {
    let message: LocalizedStringKey
    private let tailHeight: CGFloat = 14

    var body: some View {
        Text(message)
            .font(.callout.weight(.heavy))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, tailHeight)
            .background(SpeechBubbleShape(tailHeight: tailHeight).fill(.white))
            .overlay(SpeechBubbleShape(tailHeight: tailHeight).stroke(.black, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

private struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 16
    var tailWidth: CGFloat = 20
    var tailHeight: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - tailHeight))
        var path = Path(roundedRect: body, cornerRadius: cornerRadius)
        var tail = Path()
        let cx = rect.midX
        tail.move(to: CGPoint(x: cx - tailWidth / 2, y: body.maxY - 1))
        tail.addLine(to: CGPoint(x: cx - tailWidth * 0.1, y: rect.maxY))
        tail.addLine(to: CGPoint(x: cx + tailWidth / 2, y: body.maxY - 1))
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}

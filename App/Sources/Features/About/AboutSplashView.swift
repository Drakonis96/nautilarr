import SwiftUI
import NautilarrCore

/// A playful "about" splash: the Nautilarr submarine cruises through an animated
/// swell, gently dodging the logos of every service it can connect to, with a
/// short description of the app at the bottom. Reached by tapping the brand logo
/// or wordmark anywhere it appears (sidebar header, Settings). Works on every
/// platform (iPhone tab bar reaches it through the Settings brand mark).
struct AboutSplashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let repoURL = URL(string: "https://github.com/drakonis96/nautilarr")!

    /// Every service that ships a logo — these are the obstacles the sub dodges.
    private let services: [ServiceType] = ServiceType.allCases.filter { $0.logoAssetName != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                // Deep-ocean backdrop (intentionally themed, independent of the
                // app's pastel background so the scene always reads as "the sea").
                LinearGradient(
                    colors: [Theme.navy, Theme.navy.opacity(0.92), Theme.teal.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    title
                    OceanScene(services: services)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    descriptionCard
                        .padding(.horizontal, 20)
                    githubButton
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                }
            }
            .doneToolbar { dismiss() }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(.white)
    }

    private var title: some View {
        VStack(spacing: 2) {
            Text("nautilARR")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Your fleet of self-hosted services, in one harbour")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 18)
        .padding(.horizontal, 24)
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steer your whole stack")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Nautilarr is an open-source command deck for your self-hosted media setup. Browse and manage your libraries, watch the download queue, request new titles, chase missing subtitles, keep an eye on indexers, streams and server health — all from one native app on iPhone, iPad and Mac.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18)))
    }

    private var githubButton: some View {
        Button {
            openURL(repoURL)
        } label: {
            HStack(spacing: 8) {
                Image("logo-github")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("View on GitHub").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animated ocean scene

private struct OceanScene: View {
    let services: [ServiceType]
    /// Pointer location (Mac/iPad trackpad). When present, nearby service logos
    /// drift away from it; the submarine ignores it and keeps navigating.
    @State private var hover: CGPoint?

    var body: some View {
        TimelineView(.animation) { timeline in
            // Keep the magnitude small so sin()/modulo stay smooth and precise.
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    // Layered swell for depth.
                    WaveShape(phase: t * 0.7, amplitude: 9, wavelength: size.width / 1.3, baseline: 0.16)
                        .fill(Theme.teal.opacity(0.22))
                    WaveShape(phase: t * 1.05 + 1.4, amplitude: 13, wavelength: size.width, baseline: 0.22)
                        .fill(Theme.teal.opacity(0.16))

                    // Drifting bubbles for a little life.
                    ForEach(0..<10, id: \.self) { i in
                        let b = bubble(idx: i, t: t, size: size)
                        Circle()
                            .fill(.white.opacity(0.10))
                            .frame(width: b.r, height: b.r)
                            .position(b.point)
                    }

                    // Service logos floating past, behind the sub. They scatter
                    // away from the pointer when it comes near.
                    ForEach(Array(services.enumerated()), id: \.offset) { idx, type in
                        let base = obstacle(idx: idx, t: t, size: size)
                        ServiceIcon(type: type, size: 34)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            .position(repelled(base, size: size))
                    }

                    // The Nautilarr — fixed in the middle, simply bobbing along
                    // the swell so the motion always reads as smooth "sailing".
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .rotationEffect(.degrees(sin(t * 1.1) * 4))
                        .shadow(color: Theme.navy.opacity(0.5), radius: 10, y: 6)
                        .position(submarine(t: t, size: size))
                }
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case let .active(location): hover = location
                    case .ended: hover = nil
                    }
                }
            }
        }
    }

    // MARK: Motion maths

    private func obstacle(idx: Int, t: Double, size: CGSize) -> CGPoint {
        let count = max(services.count, 1)
        let travel = Double(size.width) + 200
        let spacing = travel / Double(count)
        let speed = 46.0
        let raw = (t * speed + Double(idx) * spacing).truncatingRemainder(dividingBy: travel)
        // Drift left→right so the world streams forward past the sub, making it
        // read as "the Nautilarr is advancing" rather than backing up.
        let x = -100 + raw
        // Four vertical lanes, lightly bobbing out of phase, kept clear of the
        // centred submarine's lane.
        let lanes: [Double] = [0.20, 0.34, 0.66, 0.80]
        let y = Double(size.height) * lanes[idx % lanes.count] + sin(t * 0.9 + Double(idx)) * 7
        return CGPoint(x: x, y: y)
    }

    /// Pushes a point away from the pointer within a radius.
    private func repelled(_ p: CGPoint, size: CGSize) -> CGPoint {
        guard let hover else { return p }
        let dx = p.x - hover.x
        let dy = p.y - hover.y
        let dist = max(sqrt(dx * dx + dy * dy), 0.001)
        let radius: CGFloat = 130
        guard dist < radius else { return p }
        let push = (1 - dist / radius) * 60
        return CGPoint(x: p.x + dx / dist * push, y: p.y + dy / dist * push)
    }

    private func submarine(t: Double, size: CGSize) -> CGPoint {
        let bob = sin(t * 1.2) * 12
        return CGPoint(x: Double(size.width) * 0.5, y: Double(size.height) * 0.5 + bob)
    }

    private func bubble(idx: Int, t: Double, size: CGSize) -> (point: CGPoint, r: CGFloat) {
        let h = Double(size.height) + 40
        let speed = 18.0 + Double(idx % 4) * 6
        let raw = (t * speed + Double(idx) * 53).truncatingRemainder(dividingBy: h)
        let y = h - raw
        let x = (Double(size.width) * (0.1 + 0.08 * Double(idx))) + sin(t * 1.3 + Double(idx)) * 12
        let r = CGFloat(4 + (idx % 3) * 3)
        return (CGPoint(x: x, y: y), r)
    }
}

// MARK: - Wave shape

private struct WaveShape: Shape {
    var phase: Double
    var amplitude: Double
    var wavelength: Double
    /// Where the wave's mid-line sits, as a fraction of the height.
    var baseline: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.height * baseline
        path.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        while x <= rect.width {
            let rel = Double(x) / max(wavelength, 1)
            let y = midY + CGFloat(sin(rel * 2 * .pi + phase) * amplitude)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

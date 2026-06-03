import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Scrolls the currently-visible vertical scroll view back to the top. Works
/// app-wide without each screen having to expose a `ScrollViewReader`: SwiftUI
/// `List`/`Form`/`ScrollView` are all `UIScrollView`-backed, so this reaches
/// into the active UIKit window and scrolls the main content the user is looking
/// at.
enum ScrollToTop {
    static func trigger() {
        #if canImport(UIKit)
        guard let window = activeWindow(),
              let scrollView = bestScrollView(in: window) else { return }
        let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
        scrollView.setContentOffset(top, animated: true)
        #endif
    }

    #if canImport(UIKit)
    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }

    /// The largest visible, vertically-scrollable scroll view — i.e. the main
    /// content pane, not a horizontal poster carousel or the (narrower) iPad
    /// sidebar.
    private static func bestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        for scrollView in scrollViews(in: root) {
            guard scrollView.window != nil, !scrollView.isHidden, scrollView.alpha > 0.01,
                  scrollView.bounds.width > 1, scrollView.bounds.height > 1 else { continue }
            // Vertically scrollable only (skip horizontal rows that can't scroll up).
            let inset = scrollView.adjustedContentInset
            let scrollableHeight = scrollView.contentSize.height + inset.top + inset.bottom
            guard scrollableHeight > scrollView.bounds.height + 1 else { continue }
            let frameInRoot = scrollView.convert(scrollView.bounds, to: root)
            let visible = frameInRoot.intersection(root.bounds)
            guard !visible.isNull else { continue }
            let area = visible.width * visible.height
            if area > bestArea { bestArea = area; best = scrollView }
        }
        return best
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var out: [UIScrollView] = []
        for sub in view.subviews {
            if let scrollView = sub as? UIScrollView { out.append(scrollView) }
            out.append(contentsOf: scrollViews(in: sub))
        }
        return out
    }
    #endif
}

extension View {
    /// Overlays the bottom-right floating button stack: a "scroll to top" arrow
    /// and a quick-access "fan" button that springs out the next few navigation
    /// sections. Both are individually toggleable. Applied at the navigation-
    /// stack level so they appear on every screen.
    func floatingButtons(
        scrollToTop: Bool,
        quickNav: Bool,
        quickDestinations: [AppDestination],
        onSelect: @escaping (AppDestination) -> Void
    ) -> some View {
        modifier(FloatingButtonsModifier(
            scrollToTopEnabled: scrollToTop,
            quickNavEnabled: quickNav,
            destinations: Array(quickDestinations.prefix(3)),
            onSelect: onSelect
        ))
    }
}

private struct FloatingButtonsModifier: ViewModifier {
    let scrollToTopEnabled: Bool
    let quickNavEnabled: Bool
    let destinations: [AppDestination]
    let onSelect: (AppDestination) -> Void

    @State private var expanded = false

    private var showsFan: Bool { quickNavEnabled && !destinations.isEmpty }

    /// Hand-tuned arc offsets (relative to the fan button) — they open up-and-
    /// left into open water, spaced so the icons don't crowd each other, clearing
    /// the (lifted) arrow above and the tab bar below.
    private let arc: [CGSize] = [
        CGSize(width: -100, height: 0),
        CGSize(width: -89, height: -46),
        CGSize(width: -57, height: -82)
    ]

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                if expanded {
                    // Invisible scrim: tap anywhere else to close the fan.
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { expanded = false } }
                }
                VStack(spacing: 12) {
                    if scrollToTopEnabled {
                        circleButton(system: "arrow.up", label: "Scroll to top") { ScrollToTop.trigger() }
                            // Lift the arrow while the fan is open so the top fan
                            // icon has clear, even spacing beneath it.
                            .offset(y: (showsFan && expanded) ? -44 : 0)
                    }
                    if showsFan { fan }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var fan: some View {
        ZStack {
            ForEach(Array(destinations.enumerated()), id: \.element) { index, dest in
                let offset = arc[min(index, arc.count - 1)]
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { expanded = false }
                    onSelect(dest)
                } label: {
                    Image(systemName: dest.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .glassCircle()
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                .accessibilityLabel(Text(LocalizedStringKey(dest.title)))
                .offset(x: expanded ? offset.width : 0, y: expanded ? offset.height : 0)
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.3)
            }
            circleButton(system: "ellipsis", label: "Quick access") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { expanded.toggle() }
            }
            .rotationEffect(.degrees(expanded ? 90 : 0))
        }
    }

    private func circleButton(system: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.headline.weight(.bold))
                .frame(width: 46, height: 46)
        }
        .glassCircle()
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .accessibilityLabel(label)
    }
}

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
    /// Overlays a floating "scroll to top" button in the bottom-leading corner
    /// when `enabled`. Applied at the navigation-stack level so it appears on
    /// every screen.
    func scrollToTopButton(enabled: Bool) -> some View {
        modifier(ScrollToTopButtonModifier(enabled: enabled))
    }
}

private struct ScrollToTopButtonModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if enabled {
                Button {
                    ScrollToTop.trigger()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 46, height: 46)
                }
                .glassCircle()
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityLabel("Scroll to top")
            }
        }
    }
}

import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case feed, explore, profile

    var id: Self { self }

    var title: String {
        switch self {
        case .feed: return "Лента"
        case .explore: return "Обзор"
        case .profile: return "Профиль"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "flame"
        case .explore: return "magnifyingglass"
        case .profile: return "person.crop.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .feed: return "flame.fill"
        case .explore: return "magnifyingglass"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

/// App-wide state of the top header and the floating tab bar.
/// Scrolling down hides the header and the tab bar, scrolling up brings them back.
@MainActor
@Observable
final class AppChrome {
    static let shared = AppChrome()

    var selectedTab: AppTab = .feed
    private(set) var barsHidden = false
    private(set) var scrollToTopSignal = 0

    private var lastOffset: CGFloat?
    private var travel: CGFloat = 0

    func showBars() {
        guard barsHidden else { return }
        withAnimation(.snappy(duration: 0.32)) { barsHidden = false }
    }

    func hideBars() {
        guard !barsHidden else { return }
        withAnimation(.snappy(duration: 0.32)) { barsHidden = true }
    }

    func resetScrollTracking() {
        lastOffset = nil
        travel = 0
        showBars()
    }

    func scrollToTop() {
        scrollToTopSignal += 1
        showBars()
    }

    /// `offset` is the distance scrolled from the top of the content (grows when scrolling down).
    func track(offset: CGFloat) {
        defer { lastOffset = offset }
        guard let last = lastOffset else { return }
        let delta = offset - last
        guard delta != 0 else { return }
        if offset < 60 {
            travel = 0
            showBars()
            return
        }
        // Ignore jumps caused by content resets rather than finger movement.
        guard abs(delta) < 400 else { return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel > 24 {
            hideBars()
        } else if travel < -24 {
            showBars()
        }
    }
}

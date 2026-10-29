import SwiftUI
import UIKit

@main
struct ReactorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await AuthStore.shared.restore() }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { SeenPosts.shared.flush() }
        }
    }
}

struct RootView: View {
    @State private var routers: [AppTab: Router] = [.feed: Router(), .explore: Router(), .profile: Router()]
    @State private var opened: Set<AppTab> = [.feed]

    private var chrome: AppChrome { .shared }

    private func router(_ tab: AppTab) -> Router {
        routers[tab] ?? Router()
    }

    /// The tab bar lives only on tab root screens, pushed screens get the full height.
    private var tabBarVisible: Bool {
        router(chrome.selectedTab).path.isEmpty
    }

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if opened.contains(tab) {
                    let selected = chrome.selectedTab == tab
                    TabRoot(router: router(tab)) {
                        rootView(for: tab)
                    }
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
                }
            }
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: chrome.selectedTab, onSelect: select)
                .offset(y: tabBarVisible && !chrome.barsHidden ? 0 : 160)
                .animation(.snappy(duration: 0.3), value: tabBarVisible)
        }
        .overlay(alignment: .top) { ToastOverlay() }
        .onChange(of: chrome.selectedTab) {
            opened.insert(chrome.selectedTab)
            chrome.resetScrollTracking()
        }
        .onChange(of: router(chrome.selectedTab).path.count) {
            if tabBarVisible { chrome.resetScrollTracking() }
        }
    }

    @ViewBuilder
    private func rootView(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedView()
        case .explore: ExploreView()
        case .profile: ProfileView()
        }
    }

    private func select(_ tab: AppTab) {
        UISelectionFeedbackGenerator().selectionChanged()
        if tab == chrome.selectedTab {
            let current = router(tab)
            if current.path.isEmpty {
                chrome.scrollToTop()
            } else {
                current.popToRoot()
            }
        } else {
            chrome.selectedTab = tab
        }
    }
}

/// NavigationStack with its own router; joyreactor links open inside the app.
struct TabRoot<Content: View>: View {
    @Bindable var router: Router
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack(path: $router.path) {
            content()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: FloatingTabBar.reservedHeight)
                }
                .reactorDestinations()
        }
        .environment(router)
        .environment(\.openURL, OpenURLAction { url in router.handle(url) })
    }
}

/// Floating tab bar that slides away while scrolling down.
struct FloatingTabBar: View {
    static let reservedHeight: CGFloat = 68

    let selection: AppTab
    let onSelect: (AppTab) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.bottom, 4)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 24)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(width: 76, height: 50)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.14))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

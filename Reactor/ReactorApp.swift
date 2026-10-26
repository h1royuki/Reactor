import SwiftUI

@main
struct ReactorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await AuthStore.shared.restore() }
        }
    }
}

struct RootView: View {
    enum Tab: Hashable { case feed, explore, profile }

    @State private var tab: Tab = .feed

    var body: some View {
        TabView(selection: $tab) {
            TabRoot { FeedView() }
                .tabItem { Label("Лента", systemImage: "flame") }
                .tag(Tab.feed)
            TabRoot { ExploreView() }
                .tabItem { Label("Обзор", systemImage: "magnifyingglass") }
                .tag(Tab.explore)
            TabRoot { ProfileView() }
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .overlay(alignment: .top) { ToastOverlay() }
    }
}

/// NavigationStack with its own router; joyreactor links open inside the app.
struct TabRoot<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            content()
                .reactorDestinations()
        }
        .environment(router)
        .environment(\.openURL, OpenURLAction { url in router.handle(url) })
    }
}

import SwiftUI

enum Route: Hashable {
    case post(Post)
    case postID(String)
    case tag(String)
    case user(String)
    case favorites
    case subscriptions
    case settings
    case search(String)
    /// Posts list without the profile header (the profile tab already shows it).
    case userPosts(String)
}

/// Per-tab navigation state; also turns joyreactor links into in-app navigation.
@MainActor
@Observable
final class Router {
    var path = NavigationPath()

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }

    func handle(_ url: URL) -> OpenURLAction.Result {
        guard let route = Self.route(for: url) else { return .systemAction }
        push(route)
        return .handled
    }

    static func route(for url: URL) -> Route? {
        guard let host = url.host?.lowercased(),
              host.hasSuffix("reactor.cc") || host.hasSuffix("joyreactor.com") || host.hasSuffix("reactor.com")
        else { return nil }
        // Work on the raw path: on the site "+" means a space, while a real plus is "%2B".
        let components = url.path(percentEncoded: true).split(separator: "/").map(String.init)
        guard components.count >= 2 else {
            if components.isEmpty, let sub = host.split(separator: ".").first,
               !["joyreactor", "www", "m", "reactor", "old"].contains(String(sub)) {
                return .tag(String(sub))
            }
            return nil
        }
        let raw = components[1].replacingOccurrences(of: "+", with: " ")
        let value = raw.removingPercentEncoding ?? raw
        switch components[0] {
        case "post":
            guard Int(value) != nil else { return nil }
            return .postID(NodeID.encode(type: "Post", number: value))
        case "tag":
            return .tag(value)
        case "user":
            return .user(value)
        default:
            return nil
        }
    }
}

extension View {
    @MainActor
    func reactorDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .post(let post): PostDetailView(post: post)
            case .postID(let id): PostDetailView(postID: id)
            case .tag(let name): TagView(name: name)
            case .user(let name): UserView(username: name)
            case .favorites: PostListScreen(title: "Избранное", source: .favorites)
            case .subscriptions: SubscriptionsView()
            case .settings: SettingsView()
            case .search(let query): PostListScreen(title: query, source: .search(query: query))
            case .userPosts(let name): PostListScreen(title: "Мои посты", source: .user(username: name))
            }
        }
    }
}

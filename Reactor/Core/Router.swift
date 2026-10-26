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
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else {
            if components.isEmpty, let sub = host.split(separator: ".").first,
               !["joyreactor", "www", "m", "reactor", "old"].contains(String(sub)) {
                return .tag(String(sub))
            }
            return nil
        }
        let value = components[1].removingPercentEncoding ?? components[1]
        switch components[0] {
        case "post":
            guard Int(value) != nil else { return nil }
            return .postID(NodeID.encode(type: "Post", number: value))
        case "tag":
            return .tag(value.replacingOccurrences(of: "+", with: " "))
        case "user":
            return .user(value.replacingOccurrences(of: "+", with: " "))
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
            }
        }
    }
}

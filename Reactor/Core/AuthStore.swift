import Foundation

@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var user: UserRef?
    private(set) var isRestoring = false

    var isLoggedIn: Bool { user != nil }

    private init() {
        GraphQLClient.shared.token = Keychain.get("token")
        if let id = UserDefaults.standard.string(forKey: "userID"),
           let name = UserDefaults.standard.string(forKey: "username") {
            user = UserRef(id: id, username: name)
        }
    }

    /// Re-validates the stored session on launch.
    func restore() async {
        guard user != nil else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            if let me = try await API.me() {
                store(UserRef(id: me.id, username: me.username), token: nil)
            } else {
                clear()
            }
        } catch {
            // Offline or server hiccup: keep the cached identity.
        }
    }

    func login(name: String, password: String) async throws {
        let me = try await API.login(name: name, password: password)
        store(UserRef(id: me.id, username: me.username), token: me.token)
    }

    func logout() async {
        await API.logout()
        clear()
    }

    private func store(_ user: UserRef, token: String?) {
        self.user = user
        UserDefaults.standard.set(user.id, forKey: "userID")
        UserDefaults.standard.set(user.username, forKey: "username")
        if let token {
            Keychain.set(token, for: "token")
            GraphQLClient.shared.token = token
        }
    }

    private func clear() {
        user = nil
        UserDefaults.standard.removeObject(forKey: "userID")
        UserDefaults.standard.removeObject(forKey: "username")
        Keychain.set(nil, for: "token")
        GraphQLClient.shared.token = nil
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains("joyreactor") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }
}

import SwiftUI

/// Shared optimistic state for votes/favorites so every screen shows the same values.
@MainActor
@Observable
final class InteractionStore {
    static let shared = InteractionStore()

    struct Snapshot: Equatable {
        var rating: Double
        var vote: Double?
        var favorite: Bool
    }

    private var posts: [String: Snapshot] = [:]
    private var comments: [String: Snapshot] = [:]
    private(set) var pending: Set<String> = []

    func state(for post: Post) -> Snapshot {
        posts[post.id] ?? Snapshot(rating: post.rating, vote: post.vote?.power, favorite: post.favorite)
    }

    func state(for comment: Comment) -> Snapshot {
        comments[comment.id] ?? Snapshot(rating: comment.rating, vote: comment.vote?.power, favorite: false)
    }

    func vote(post: Post, plus: Bool) async {
        guard ensureLoggedIn(), !pending.contains(post.id) else { return }
        pending.insert(post.id)
        defer { pending.remove(post.id) }
        do {
            let result = try await API.vote(id: post.id, plus: plus)
            var current = state(for: post)
            current.rating = result.rating
            current.vote = result.vote?.power ?? (plus ? 1 : -1)
            posts[post.id] = current
            Haptics.tap()
        } catch {
            ToastCenter.shared.show(error)
        }
    }

    func vote(comment: Comment, plus: Bool) async {
        guard ensureLoggedIn(), !pending.contains(comment.id) else { return }
        pending.insert(comment.id)
        defer { pending.remove(comment.id) }
        do {
            let result = try await API.vote(id: comment.id, plus: plus)
            var current = state(for: comment)
            current.rating = result.rating
            current.vote = result.vote?.power ?? (plus ? 1 : -1)
            comments[comment.id] = current
            Haptics.tap()
        } catch {
            ToastCenter.shared.show(error)
        }
    }

    func toggleFavorite(post: Post) async {
        guard ensureLoggedIn(), !pending.contains(post.id) else { return }
        pending.insert(post.id)
        defer { pending.remove(post.id) }
        var current = state(for: post)
        do {
            current.favorite = try await API.setFavorite(id: post.id, !current.favorite)
            posts[post.id] = current
            Haptics.tap()
            ToastCenter.shared.show(current.favorite ? "Добавлено в избранное" : "Убрано из избранного")
        } catch {
            ToastCenter.shared.show(error)
        }
    }

    private func ensureLoggedIn() -> Bool {
        if AuthStore.shared.isLoggedIn { return true }
        ToastCenter.shared.show("Войдите в аккаунт во вкладке «Профиль»")
        return false
    }
}

@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var message: String?
    private var hideTask: Task<Void, Never>?

    func show(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        show(error.localizedDescription)
    }

    func show(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { message = text }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { message = nil }
        }
    }
}

enum Haptics {
    @MainActor static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}

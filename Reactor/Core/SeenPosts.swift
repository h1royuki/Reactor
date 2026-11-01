import Foundation

/// Posts the user has already scrolled past or opened, persisted across launches.
/// Feeds that hide viewed posts skip these when loading new pages.
@MainActor
final class SeenPosts {
    static let shared = SeenPosts()

    private static let limit = 50_000

    private var ids = Set<String>()
    private var order: [String] = []
    private var saveTask: Task<Void, Never>?
    /// Per feed: how far down the user has read, so skipping viewed posts can jump instead of crawl.
    private var resumeOffsets: [String: Int] =
        (UserDefaults.standard.dictionary(forKey: "seenResumeOffsets") as? [String: Int]) ?? [:]

    private let fileURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("seen-posts.json")
    }()

    var count: Int { ids.count }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String].self, from: data) {
            order = stored
            ids = Set(stored)
        }
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func mark(_ id: String) {
        guard ids.insert(id).inserted else { return }
        order.append(id)
        if order.count > Self.limit {
            let overflow = order.count - Self.limit
            order.prefix(overflow).forEach { ids.remove($0) }
            order.removeFirst(overflow)
        }
        scheduleSave()
    }

    func reset() {
        ids.removeAll()
        order.removeAll()
        resumeOffsets.removeAll()
        UserDefaults.standard.removeObject(forKey: "seenResumeOffsets")
        scheduleSave()
    }

    func resumeOffset(for key: String) -> Int? {
        resumeOffsets[key]
    }

    /// Only moves forward: reading a few fresh posts at the top must not lose the deeper position.
    func updateResumeOffset(_ offset: Int, for key: String) {
        guard offset > (resumeOffsets[key] ?? 0) else { return }
        resumeOffsets[key] = offset
        UserDefaults.standard.set(resumeOffsets, forKey: "seenResumeOffsets")
    }

    /// Writes pending changes right away (the app is going to the background).
    func flush() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    /// Batches writes: scrolling marks posts one by one.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        let snapshot = order
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

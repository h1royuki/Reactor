import SwiftUI

@MainActor
@Observable
final class PostListModel {
    let source: PostSource

    private(set) var posts: [Post] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var reachedEnd = false
    private(set) var loadedOnce = false

    private var offset = 0
    private var seen = Set<String>()
    private var generation = 0
    private var loadedWithNSFW: Bool?

    init(source: PostSource) {
        self.source = source
    }

    func loadIfNeeded() async {
        if loadedWithNSFW != nil, loadedWithNSFW != AppSettings.shared.showNSFW {
            await refresh()
            return
        }
        guard !loadedOnce, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        generation += 1
        let gen = generation
        await load(reset: true, generation: gen)
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, error == nil, loadedOnce else { return }
        await load(reset: false, generation: generation)
    }

    func retry() async {
        error = nil
        if posts.isEmpty { await refresh() } else { await loadMore() }
    }

    private func load(reset: Bool, generation gen: Int) async {
        isLoading = true
        if reset { error = nil }
        let nsfw = AppSettings.shared.showNSFW
        var startOffset = reset ? 0 : offset
        var seenIDs = reset ? Set<String>() : seen
        var collected: [Post] = []
        var ended = false
        var attempts = 0
        do {
            repeat {
                let batch = try await API.posts(source, offset: startOffset, nsfw: nsfw)
                guard gen == generation else { return }
                startOffset += batch.count
                if batch.isEmpty || !source.isPaged { ended = true }
                for post in batch where !seenIDs.contains(post.id) {
                    seenIDs.insert(post.id)
                    if nsfw || !post.isAdult { collected.append(post) }
                }
                attempts += 1
            } while collected.isEmpty && !ended && attempts < 6
            offset = startOffset
            seen = seenIDs
            reachedEnd = ended
            if reset { posts = collected } else { posts.append(contentsOf: collected) }
            loadedOnce = true
            loadedWithNSFW = nsfw
            error = nil
        } catch {
            if gen == generation, !error.isCancellation {
                self.error = error.localizedDescription
                loadedOnce = true
            }
        }
        if gen == generation { isLoading = false }
    }
}

/// Keeps one model per source so switching tabs/filters preserves loaded pages.
final class PostListModelStore {
    private var models: [PostSource: PostListModel] = [:]

    @MainActor
    func model(for source: PostSource) -> PostListModel {
        if let model = models[source] { return model }
        let model = PostListModel(source: source)
        models[source] = model
        return model
    }
}

/// Infinite scrolling list of post cards with an optional header.
struct PostFeed<Header: View>: View {
    let model: PostListModel
    @ViewBuilder var header: () -> Header

    init(model: PostListModel, @ViewBuilder header: @escaping () -> Header) {
        self.model = model
        self.header = header
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header()

                ForEach(model.posts) { post in
                    PostCard(post: post)
                        .onAppear {
                            if model.posts.suffix(4).contains(where: { $0.id == post.id }) {
                                Task { await model.loadMore() }
                            }
                        }
                    SectionSeparator()
                }

                footer
            }
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = model.error {
            ErrorStateView(message: error) {
                Task { await model.retry() }
            }
            .padding(.top, model.posts.isEmpty ? 80 : 0)
        } else if model.isLoading {
            ProgressView()
                .controlSize(.large)
                .padding(40)
                .frame(maxWidth: .infinity)
                .padding(.top, model.posts.isEmpty ? 80 : 0)
        } else if model.loadedOnce && model.posts.isEmpty {
            ContentUnavailableView("Здесь пока пусто", systemImage: "tray",
                                   description: Text(AppSettings.shared.showNSFW ? "" : "Часть постов может быть скрыта фильтром 18+"))
                .padding(.top, 60)
        } else if model.reachedEnd && !model.posts.isEmpty {
            Text("Это всё")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(30)
        }
    }
}

extension PostFeed where Header == EmptyView {
    init(model: PostListModel) {
        self.init(model: model) { EmptyView() }
    }
}

/// Simple screen wrapper: title + feed.
struct PostListScreen: View {
    let title: String
    let source: PostSource

    @State private var store = PostListModelStore()

    var body: some View {
        PostFeed(model: store.model(for: source))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

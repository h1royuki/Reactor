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
    /// Viewed posts passed over during the current load (shown while scanning).
    private(set) var skippedCount = 0
    /// The scan hit its per-load limit without finding anything new; the user can ask to continue.
    private(set) var exhaustedScan = false

    private var offset = 0
    private var seen = Set<String>()
    private var generation = 0
    private var loadedWithNSFW: Bool?
    private var loadedWithHideSeen: Bool?

    init(source: PostSource) {
        self.source = source
    }

    func loadIfNeeded() async {
        let settings = AppSettings.shared
        if loadedWithNSFW != nil,
           loadedWithNSFW != settings.showNSFW || loadedWithHideSeen != settings.hideSeen {
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

    private struct Cursor {
        var offset: Int
        var known: Set<String>
        var ended = false
    }

    private static let pageSize = 10
    /// Pages checked per request while skipping viewed posts (ids only, so it stays light).
    private static let scanPages = 20
    /// Requests per load before asking the user whether to keep looking.
    private static let maxScanRounds = 40

    private func load(reset: Bool, generation gen: Int) async {
        isLoading = true
        exhaustedScan = false
        skippedCount = 0
        if reset { error = nil }
        let nsfw = AppSettings.shared.showNSFW
        let hideSeen = AppSettings.shared.hideSeen && source.hidesSeen
        var cursor = Cursor(offset: reset ? 0 : offset, known: reset ? [] : seen)
        do {
            let collected: [Post]
            if hideSeen, case .tag(let name, let line) = source {
                collected = try await loadUnseen(name: name, line: line, cursor: &cursor, nsfw: nsfw, generation: gen)
            } else {
                collected = try await loadSequential(cursor: &cursor, nsfw: nsfw, generation: gen)
            }
            offset = cursor.offset
            seen = cursor.known
            reachedEnd = cursor.ended
            if reset { posts = collected } else { posts.append(contentsOf: collected) }
            loadedOnce = true
            loadedWithNSFW = nsfw
            loadedWithHideSeen = AppSettings.shared.hideSeen
            error = nil
        } catch {
            if gen == generation, !error.isCancellation {
                self.error = error.localizedDescription
                loadedOnce = true
            }
        }
        if gen == generation { isLoading = false }
    }

    private func checkCurrent(_ gen: Int) throws {
        if gen != generation { throw CancellationError() }
    }

    /// Keeps posts not shown yet in this list, minus 18+ and (optionally) viewed ones.
    private func accept(_ batch: [Post], cursor: inout Cursor, nsfw: Bool, hideSeen: Bool) -> [Post] {
        var result: [Post] = []
        for post in batch where cursor.known.insert(post.id).inserted {
            guard nsfw || !post.isAdult else { continue }
            guard !hideSeen || !SeenPosts.shared.contains(post.id) else { continue }
            result.append(post)
        }
        return result
    }

    private func loadSequential(cursor: inout Cursor, nsfw: Bool, generation gen: Int) async throws -> [Post] {
        var collected: [Post] = []
        var attempts = 0
        repeat {
            let batch = try await API.posts(source, offset: cursor.offset, nsfw: nsfw)
            try checkCurrent(gen)
            cursor.offset += batch.count
            if batch.isEmpty || !source.isPaged { cursor.ended = true }
            collected += accept(batch, cursor: &cursor, nsfw: nsfw, hideSeen: false)
            attempts += 1
        } while collected.isEmpty && !cursor.ended && attempts < 6
        // Six pages in a row were all filtered out (e.g. 18+): let the user keep looking
        // instead of claiming the feed is empty.
        if collected.isEmpty && !cursor.ended { exhaustedScan = true }
        return collected
    }

    /// Feed with viewed posts hidden. Fresh posts usually sit right at the cursor, so one normal page
    /// goes first; when it is all viewed, the feed is scanned by ids 200 posts per request, jumping to
    /// where the user stopped reading last time, and full posts are fetched only where something is new.
    private func loadUnseen(name: String?, line: PostLineType, cursor: inout Cursor,
                            nsfw: Bool, generation gen: Int) async throws -> [Post] {
        let seenStore = SeenPosts.shared
        let resumeKey = source.resumeKey
        defer {
            if let resumeKey { seenStore.updateResumeOffset(cursor.offset, for: resumeKey) }
        }

        let first = try await API.posts(source, offset: cursor.offset, nsfw: nsfw)
        try checkCurrent(gen)
        cursor.offset += first.count
        if first.isEmpty {
            cursor.ended = true
            return []
        }
        let fresh = accept(first, cursor: &cursor, nsfw: nsfw, hideSeen: true)
        if !fresh.isEmpty { return fresh }

        var jumped = false
        for _ in 0..<Self.maxScanRounds {
            let offsets = (0..<Self.scanPages).map { cursor.offset + $0 * Self.pageSize }
            let pages = try await API.tagPostStubs(name: name, line: line, offsets: offsets)
            try checkCurrent(gen)

            let filled = pages.prefix { !$0.isEmpty }
            let hit = filled.firstIndex { page in
                page.contains { stub in
                    !cursor.known.contains(stub.id) && (nsfw || !stub.isAdult) && !seenStore.contains(stub.id)
                }
            }

            guard let hit else {
                skippedCount += filled.reduce(0) { $0 + $1.count }
                if filled.count < pages.count {
                    cursor.ended = true
                    return []
                }
                cursor.offset = offsets[offsets.count - 1] + Self.pageSize
                // Everything near the top is read: continue from where reading stopped last time.
                // The list only grows at the top, so the old position now sits a bit lower; starting
                // 200 posts earlier stays on the safe side.
                if !jumped, let resumeKey, let resume = seenStore.resumeOffset(for: resumeKey),
                   resume - 200 > cursor.offset {
                    cursor.offset = resume - 200
                    jumped = true
                }
                continue
            }

            skippedCount += filled.prefix(hit).reduce(0) { $0 + $1.count }
            let pageOffsets = [offsets[hit], offsets[hit] + Self.pageSize]
            let full = try await API.tagPosts(name: name, line: line, offsets: pageOffsets)
            try checkCurrent(gen)
            if full[1].isEmpty {
                cursor.offset = pageOffsets[0] + full[0].count
                if full[0].isEmpty { cursor.ended = true }
            } else {
                cursor.offset = pageOffsets[1] + full[1].count
            }
            let result = accept(full.flatMap { $0 }, cursor: &cursor, nsfw: nsfw, hideSeen: true)
            if !result.isEmpty || cursor.ended { return result }
        }
        exhaustedScan = true
        return []
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
    /// Drives the hide-on-scroll header and tab bar (only for tab root feeds).
    var tracksChrome = false
    @ViewBuilder var header: () -> Header

    @State private var baseline: CGFloat?

    private static var topAnchor: String { "feed-top" }
    private static var space: String { "feed-scroll" }

    init(model: PostListModel, tracksChrome: Bool = false, @ViewBuilder header: @escaping () -> Header) {
        self.model = model
        self.tracksChrome = tracksChrome
        self.header = header
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchor)

                    header()

                    ForEach(model.posts) { post in
                        PostCard(post: post)
                            // Viewed = the whole card has scrolled past the top.
                            .onGeometryChange(for: Bool.self) { geometry in
                                geometry.frame(in: .named(Self.space)).maxY < 0
                            } action: { scrolledPast in
                                if scrolledPast { SeenPosts.shared.mark(post.id) }
                            }
                            .onAppear {
                                if let index = model.posts.firstIndex(where: { $0.id == post.id }) {
                                    ImagePrefetcher.shared.prefetch(model.posts.dropFirst(index + 1).prefix(ImagePrefetcher.lookahead))
                                }
                                // The next page must arrive before prefetching needs its posts,
                                // plus a little time for the request itself.
                                if model.posts.suffix(ImagePrefetcher.lookahead + 2).contains(where: { $0.id == post.id }) {
                                    Task { await model.loadMore() }
                                }
                            }
                        SectionSeparator()
                    }

                    footer
                }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.frame(in: .named(Self.space)).minY
                } action: { minY in
                    guard tracksChrome else { return }
                    if baseline == nil { baseline = minY }
                    AppChrome.shared.track(offset: (baseline ?? minY) - minY)
                }
            }
            .coordinateSpace(.named(Self.space))
            .onChange(of: AppChrome.shared.scrollToTopSignal) {
                guard tracksChrome else { return }
                withAnimation(.snappy) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
        // Tabs stay alive while hidden, so .task does not rerun after a settings change.
        .onChange(of: AppSettings.shared.showNSFW) { Task { await model.refresh() } }
        .onChange(of: AppSettings.shared.hideSeen) { Task { await model.refresh() } }
    }

    private var hidingSeen: Bool {
        AppSettings.shared.hideSeen && model.source.hidesSeen && SeenPosts.shared.count > 0
    }

    private var emptyTitle: String { hidingSeen ? "Вы всё посмотрели" : "Здесь пока пусто" }
    private var emptyIcon: String { hidingSeen ? "checkmark.circle" : "tray" }

    private var emptyDescription: String {
        if hidingSeen { return "Просмотренные посты скрыты. Их можно вернуть в настройках." }
        return AppSettings.shared.showNSFW ? "" : "Часть постов может быть скрыта фильтром 18+"
    }

    @ViewBuilder
    private var footer: some View {
        if let error = model.error {
            ErrorStateView(message: error) {
                Task { await model.retry() }
            }
            .padding(.top, model.posts.isEmpty ? 80 : 0)
        } else if model.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                if model.skippedCount > 0 {
                    Text("Пропускаем просмотренные: \(model.skippedCount)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
            .padding(.top, model.posts.isEmpty ? 80 : 0)
        } else if model.exhaustedScan {
            VStack(spacing: 12) {
                Text("Подряд идут только скрытые посты — просмотренные или 18+")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Искать дальше") {
                    Task { await model.loadMore() }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .padding(.top, model.posts.isEmpty ? 80 : 0)
        } else if model.loadedOnce && model.posts.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyDescription))
                .padding(.top, 60)
        } else if model.reachedEnd && !model.posts.isEmpty {
            Text("Это всё")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(30)
        } else if model.loadedOnce {
            // Safety net: reaching the bottom always asks for more, even if no card triggered it.
            Color.clear
                .frame(height: 1)
                .onAppear { Task { await model.loadMore() } }
        }
    }
}

extension PostFeed where Header == EmptyView {
    init(model: PostListModel, tracksChrome: Bool = false) {
        self.init(model: model, tracksChrome: tracksChrome) { EmptyView() }
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

import SwiftUI
import UIKit

struct CommentNode: Identifiable {
    let comment: Comment
    let depth: Int
    let childCount: Int
    var id: String { comment.id }

    static func flatten(_ comments: [Comment], postID: String) -> [CommentNode] {
        let ids = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments) { comment -> String in
            guard let parent = comment.parent?.id, ids.contains(parent) else { return postID }
            return parent
        }
        func descendants(_ id: String) -> Int {
            (children[id] ?? []).reduce(0) { $0 + 1 + descendants($1.id) }
        }
        var result: [CommentNode] = []
        func visit(_ parent: String, depth: Int) {
            for comment in (children[parent] ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
                result.append(CommentNode(comment: comment, depth: depth, childCount: descendants(comment.id)))
                visit(comment.id, depth: depth + 1)
            }
        }
        visit(postID, depth: 0)
        return result
    }
}

struct ReplyTarget: Identifiable {
    let id: String
    let title: String
}

struct PostDetailView: View {
    let postID: String

    @State private var post: Post?
    @State private var nodes: [CommentNode] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var collapsed: Set<String> = []
    @State private var replyTarget: ReplyTarget?
    @State private var sortByRating = false

    private var auth: AuthStore { .shared }

    init(post: Post) {
        postID = post.id
        _post = State(initialValue: post)
    }

    init(postID: String) {
        self.postID = postID
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let post {
                    PostCard(post: post, collapsed: false)
                    SectionSeparator()
                    commentsHeader(post)
                } else if let error {
                    ErrorStateView(message: error) { Task { await load() } }
                        .padding(.top, 80)
                }

                if loading && nodes.isEmpty {
                    ProgressView()
                        .padding(40)
                        .frame(maxWidth: .infinity)
                }

                ForEach(visibleNodes) { node in
                    CommentRow(node: node,
                               isCollapsed: collapsed.contains(node.id),
                               onToggle: { toggle(node) },
                               onReply: { replyTarget = ReplyTarget(id: node.id, title: "Ответ \(node.comment.user.username)") })
                    Divider().padding(.leading, 16 + CGFloat(min(node.depth, CommentRow.maxIndent)) * CommentRow.indentStep)
                }

                if loaded && nodes.isEmpty && post != nil {
                    Text("Комментариев пока нет")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Пост")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if auth.isLoggedIn, post != nil {
                Button {
                    replyTarget = ReplyTarget(id: postID, title: "Комментарий")
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("Написать комментарий")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .sheet(item: $replyTarget) { target in
            CommentComposer(target: target) {
                Task { await load() }
            }
        }
    }

    private func commentsHeader(_ post: Post) -> some View {
        HStack {
            Text("Комментарии")
                .font(.title3.weight(.bold))
            Text("\(max(post.commentsCount, nodes.count))")
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Сортировка", selection: $sortByRating) {
                    Label("По порядку", systemImage: "clock").tag(false)
                    Label("Лучшие сверху", systemImage: "flame").tag(true)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var visibleNodes: [CommentNode] {
        var ordered = nodes
        if sortByRating {
            // Reorder root threads by rating, keeping replies attached to their parents.
            var threads: [[CommentNode]] = []
            for node in nodes {
                if node.depth == 0 || threads.isEmpty { threads.append([node]) } else { threads[threads.count - 1].append(node) }
            }
            ordered = threads.sorted { ($0.first?.comment.rating ?? 0) > ($1.first?.comment.rating ?? 0) }.flatMap { $0 }
        }
        var result: [CommentNode] = []
        var hideDeeperThan: Int?
        for node in ordered {
            if let limit = hideDeeperThan {
                if node.depth > limit { continue }
                hideDeeperThan = nil
            }
            result.append(node)
            if collapsed.contains(node.id) { hideDeeperThan = node.depth }
        }
        return result
    }

    private func toggle(_ node: CommentNode) {
        withAnimation(.snappy) {
            if collapsed.contains(node.id) { collapsed.remove(node.id) } else { collapsed.insert(node.id) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let (fresh, comments) = try await API.postWithComments(id: postID)
            post = fresh
            nodes = CommentNode.flatten(comments, postID: fresh.id)
            loaded = true
            error = nil
        } catch {
            if error.isCancellation { return }
            if post == nil { self.error = error.localizedDescription } else { ToastCenter.shared.show(error) }
            loaded = true
        }
    }
}

struct CommentRow: View {
    static let maxIndent = 6
    static let indentStep: CGFloat = 14

    let node: CommentNode
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onReply: () -> Void

    @State private var viewer: MediaViewerState?
    private var store: InteractionStore { .shared }
    private var auth: AuthStore { .shared }

    private var blocks: [ContentBlock] {
        BlockCache.blocks(id: node.comment.id, html: node.comment.text, attributes: node.comment.attributes)
    }

    var body: some View {
        let comment = node.comment
        let state = store.state(for: comment)
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<min(node.depth, Self.maxIndent), id: \.self) { level in
                Rectangle()
                    .fill(Self.threadColor(level).opacity(0.5))
                    .frame(width: 2)
                    .padding(.trailing, Self.indentStep - 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NavigationLink(value: Route.user(comment.user.username)) {
                        HStack(spacing: 8) {
                            AvatarView(url: comment.user.avatarURL, name: comment.user.username, size: 26)
                            Text(comment.user.username)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("· \(Formatting.date(comment.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isCollapsed {
                        Text("+\(node.childCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    VoteControl(rating: state.rating, vote: state.vote,
                                busy: store.pending.contains(comment.id), compact: true) { plus in
                        Task { await store.vote(comment: comment, plus: plus) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)

                if !isCollapsed {
                    ForEach(blocks) { block in
                        switch block {
                        case .text(let text, _):
                            Text(text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .attribute(let attribute):
                            AttributeView(attribute: attribute, maxWidth: 360) {
                                viewer = MediaViewerState(attributes: [attribute], index: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if auth.isLoggedIn {
                        Button(action: onReply) {
                            Label("Ответить", systemImage: "arrowshape.turn.up.left")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .opacity(state.rating < -5 ? 0.55 : 1)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .contextMenu {
            Button {
                UIPasteboard.general.string = ContentBuilder.plainText(html: comment.text)
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
            if auth.isLoggedIn {
                Button(action: onReply) {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left")
                }
            }
        }
        .fullScreenCover(item: $viewer) { state in
            MediaViewer(state: state)
        }
    }

    static func threadColor(_ level: Int) -> Color {
        let colors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]
        return colors[level % colors.count]
    }
}

struct CommentComposer: View {
    let target: ReplyTarget
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(.horizontal, 12)
                .navigationTitle(target.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if sending {
                            ProgressView()
                        } else {
                            Button("Отправить") { send() }
                                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        sending = true
        Task {
            defer { sending = false }
            do {
                try await API.comment(on: target.id, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                ToastCenter.shared.show("Комментарий отправлен")
                onSent()
                dismiss()
            } catch {
                ToastCenter.shared.show(error)
            }
        }
    }
}

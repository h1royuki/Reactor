import SwiftUI

@MainActor
enum BlockCache {
    private static var storage: [String: [ContentBlock]] = [:]
    private static var order: [String] = []

    static func blocks(id: String, html: String, attributes: [Attribute]) -> [ContentBlock] {
        let key = "\(id)#\(html.hashValue)"
        if let cached = storage[key] { return cached }
        let blocks = ContentBuilder.blocks(html: html, attributes: attributes)
        storage[key] = blocks
        order.append(key)
        if order.count > 400 {
            for old in order.prefix(100) { storage[old] = nil }
            order.removeFirst(100)
        }
        return blocks
    }
}

/// Post body: rich text interleaved with media.
struct PostContentView: View {
    let post: Post
    var collapsed: Bool

    @State private var viewer: MediaViewerState?

    private var blocks: [ContentBlock] {
        BlockCache.blocks(id: post.id, html: post.text, attributes: post.attributes)
    }

    var body: some View {
        let all = blocks
        let layout: (visible: [ContentBlock], clippedTextID: String?, truncated: Bool) =
            collapsed ? Self.truncate(all) : (all, nil, false)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(layout.visible) { block in
                switch block {
                case .text(let text, _):
                    Text(text)
                        .font(.body)
                        .lineLimit(block.id == layout.clippedTextID ? 8 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                case .attribute(let attribute):
                    AttributeView(attribute: attribute) {
                        open(attribute, in: all)
                    }
                }
            }
            if layout.truncated {
                NavigationLink(value: Route.post(post)) {
                    HStack(spacing: 4) {
                        Text("Показать полностью")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
        .fullScreenCover(item: $viewer) { state in
            MediaViewer(state: state)
        }
    }

    private func open(_ attribute: Attribute, in blocks: [ContentBlock]) {
        let media = blocks.compactMap { block -> Attribute? in
            if case .attribute(let a) = block, a.kind == .picture || a.kind == .gif { return a }
            return nil
        }
        guard let index = media.firstIndex(of: attribute) else { return }
        viewer = MediaViewerState(attributes: media, index: index)
    }

    /// Limits feed cards to a sane amount of text and media.
    static func truncate(_ blocks: [ContentBlock]) -> (visible: [ContentBlock], clippedTextID: String?, truncated: Bool) {
        var visible: [ContentBlock] = []
        var textBudget = 600
        var mediaBudget = 5
        for block in blocks {
            switch block {
            case .text(let text, _):
                if textBudget <= 0 { return (visible, nil, true) }
                visible.append(block)
                textBudget -= text.characters.count
                if textBudget < 0 { return (visible, block.id, true) }
            case .attribute:
                if mediaBudget == 0 { return (visible, nil, true) }
                visible.append(block)
                mediaBudget -= 1
            }
        }
        return (visible, nil, false)
    }
}

struct PollView: View {
    let post: Post
    @State private var poll: Poll
    @State private var voting = false

    init(post: Post, poll: Poll) {
        self.post = post
        _poll = State(initialValue: poll)
    }

    private var total: Int { max(poll.answers.reduce(0) { $0 + $1.count }, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(poll.question, systemImage: "chart.bar.xaxis")
                .font(.headline)
            ForEach(poll.answers) { answer in
                Button {
                    vote(answer)
                } label: {
                    let share = Double(answer.count) / Double(total)
                    ZStack(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(poll.voted ? 0.25 : 0))
                                .frame(width: proxy.size.width * share)
                        }
                        HStack {
                            Text(answer.answer)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if poll.voted {
                                Text("\(Int((share * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(poll.voted || voting)
            }
            if poll.voted {
                Text("Голосов: \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func vote(_ answer: PollAnswer) {
        guard AuthStore.shared.isLoggedIn else {
            ToastCenter.shared.show("Войдите, чтобы голосовать")
            return
        }
        voting = true
        Task {
            defer { voting = false }
            do {
                poll = try await API.pollVote(answer: answer.id, postID: post.id)
            } catch {
                ToastCenter.shared.show(error)
            }
        }
    }
}

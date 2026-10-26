import SwiftUI
import UIKit

struct PostCard: View {
    let post: Post
    var collapsed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostHeader(post: post, linkToPost: collapsed)
                .padding(.horizontal, 16)

            if !post.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.tags) { tag in
                            TagChip(name: tag.name, highlighted: tag.nsfw == true)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let header = post.header, !header.isEmpty {
                Text(HTMLText.decodeEntities(header))
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 16)
            }

            PostContentView(post: post, collapsed: collapsed)

            if let poll = post.poll {
                PollView(post: post, poll: poll)
            }

            PostActionsBar(post: post, linkToComments: collapsed)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }
}

struct PostHeader: View {
    let post: Post
    var linkToPost: Bool

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.user(post.user.username)) {
                HStack(spacing: 10) {
                    AvatarView(url: post.user.avatarURL, name: post.user.username, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.user.username)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(Formatting.date(post.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if post.isAdult {
                Text("18+")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(.white)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
            }

            Menu {
                ShareLink(item: post.webURL) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.url = post.webURL
                    ToastCenter.shared.show("Ссылка скопирована")
                } label: {
                    Label("Скопировать ссылку", systemImage: "link")
                }
                Link(destination: post.webURL) {
                    Label("Открыть в Safari", systemImage: "safari")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
    }
}

struct PostActionsBar: View {
    let post: Post
    var linkToComments: Bool

    private var store: InteractionStore { .shared }

    var body: some View {
        let state = store.state(for: post)
        HStack(spacing: 10) {
            VoteControl(rating: state.rating, vote: state.vote, busy: store.pending.contains(post.id)) { plus in
                Task { await store.vote(post: post, plus: plus) }
            }

            if linkToComments {
                NavigationLink(value: Route.post(post)) {
                    commentsLabel
                }
                .buttonStyle(.plain)
            } else {
                commentsLabel
            }

            Spacer()

            Button {
                Task { await store.toggleFavorite(post: post) }
            } label: {
                Image(systemName: state.favorite ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(state.favorite ? Color.accentColor : Color.secondary)
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
                    .symbolEffect(.bounce, value: state.favorite)
            }
            .buttonStyle(.plain)

            ShareLink(item: post.webURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var commentsLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left")
            Text("\(post.commentsCount)")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// ▲ rating ▼ capsule used for posts and comments.
struct VoteControl: View {
    let rating: Double
    let vote: Double?
    var busy = false
    var compact = false
    let onVote: (Bool) -> Void

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            Button { onVote(true) } label: {
                Image(systemName: (vote ?? 0) > 0 ? "arrowshape.up.fill" : "arrowshape.up")
                    .foregroundStyle((vote ?? 0) > 0 ? Color.green : Color.secondary)
                    .frame(width: compact ? 26 : 32, height: compact ? 26 : 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Group {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(Formatting.rating(rating))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: rating))
                }
            }
            .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
            .foregroundStyle(rating < 0 ? Color.red : Color.primary)
            .frame(minWidth: compact ? 24 : 32)

            Button { onVote(false) } label: {
                Image(systemName: (vote ?? 0) < 0 ? "arrowshape.down.fill" : "arrowshape.down")
                    .foregroundStyle((vote ?? 0) < 0 ? Color.red : Color.secondary)
                    .frame(width: compact ? 26 : 32, height: compact ? 26 : 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(compact ? .caption : .subheadline)
        .padding(.horizontal, compact ? 2 : 4)
        .background(compact ? Color.clear : Color(.tertiarySystemFill), in: Capsule())
        .disabled(busy || vote != nil)
        .animation(.snappy, value: rating)
    }
}

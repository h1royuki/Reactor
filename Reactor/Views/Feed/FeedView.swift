import SwiftUI

enum FeedKind: Hashable, Identifiable {
    case line(PostLineType)
    case weekTop

    var id: String {
        switch self {
        case .line(let type): return type.rawValue
        case .weekTop: return "weekTop"
        }
    }

    var title: String {
        switch self {
        case .line(let type): return type.title
        case .weekTop: return "Топ недели"
        }
    }

    var icon: String {
        switch self {
        case .line(let type): return type.icon
        case .weekTop: return "trophy"
        }
    }

    var source: PostSource {
        switch self {
        case .line(let type): return .tag(name: nil, type: type)
        case .weekTop: return .weekTop
        }
    }

    static var all: [FeedKind] { PostLineType.allCases.map(FeedKind.line) + [.weekTop] }
}

struct FeedView: View {
    @State private var kind: FeedKind = .line(AppSettings.shared.defaultFeed)
    @State private var store = PostListModelStore()

    private var chrome: AppChrome { .shared }

    var body: some View {
        PostFeed(model: store.model(for: kind.source), tracksChrome: true)
            .id(kind)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: FeedHeader.height)
            }
            .overlay(alignment: .top) {
                FeedHeader(kind: $kind)
                    .offset(y: chrome.barsHidden ? -FeedHeader.height : 0)
            }
            .overlay(alignment: .top) {
                // Solid status bar strip the header slides under.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
                    .background(Color(.systemBackground))
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: kind) { chrome.resetScrollTracking() }
    }
}

/// Solid top bar: logo on the leading edge, feed switcher in the middle. Hides on scroll down.
/// Search and profile live in the tab bar, so they are not repeated here.
struct FeedHeader: View {
    static let height: CGFloat = 56

    @Binding var kind: FeedKind

    var body: some View {
        ZStack {
            HStack {
                Button {
                    AppChrome.shared.scrollToTop()
                } label: {
                    Image("Logo")
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Joyreactor, наверх")
                Spacer()
            }

            Menu {
                Picker("Раздел", selection: $kind) {
                    ForEach(FeedKind.all) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: kind.icon)
                        .font(.footnote.weight(.semibold))
                    Text(kind.title)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1 / 3)
        }
    }
}

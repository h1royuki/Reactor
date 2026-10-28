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
                // Blurred status bar strip the header slides under.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
                    .background(.bar)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: kind) { chrome.resetScrollTracking() }
    }
}

/// Blurred top bar: logo on the leading edge, feed switcher as the centered title.
/// Hides on scroll down. Search and profile live in the tab bar, so they are not repeated here.
struct FeedHeader: View {
    static let height: CGFloat = 50

    @Binding var kind: FeedKind

    var body: some View {
        HStack(spacing: 0) {
            Button {
                AppChrome.shared.scrollToTop()
            } label: {
                Image("Logo")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Joyreactor, наверх")
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Picker("Раздел", selection: $kind) {
                    ForEach(FeedKind.all) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(kind.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .tint(Color.primary)
            .fixedSize()

            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        // The status bar strip has its own blur, so this one stays inside the safe area.
        .background(.bar, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1 / 3)
        }
    }
}

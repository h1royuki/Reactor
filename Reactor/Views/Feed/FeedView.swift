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

/// Solid top bar: logo, search shortcut and feed switcher. Hides on scroll down.
struct FeedHeader: View {
    static let height: CGFloat = 104

    @Binding var kind: FeedKind

    private var chrome: AppChrome { .shared }
    private var auth: AuthStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    chrome.scrollToTop()
                } label: {
                    HStack(spacing: 9) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text("Реактор")
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                headerButton("magnifyingglass") {
                    chrome.selectedTab = .explore
                }
                headerButton(auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle") {
                    chrome.selectedTab = .profile
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)

            FeedPicker(selection: $kind)
                .frame(height: 50)
        }
        .frame(height: Self.height, alignment: .top)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1 / 3)
        }
    }

    private func headerButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct FeedPicker: View {
    @Binding var selection: FeedKind

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FeedKind.all) { item in
                        let selected = item == selection
                        Button {
                            withAnimation(.snappy) { selection = item }
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(item)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: selection) {
                withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }
}

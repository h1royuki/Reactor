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

    var body: some View {
        PostFeed(model: store.model(for: kind.source)) {
            FeedPicker(selection: $kind)
        }
        .id(kind)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            ForEach(FeedKind.all) { item in
                Button {
                    kind = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Реактор")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.accentColor)
                    .fixedSize()
            }
        }
    }
}

private struct FeedPicker: View {
    @Binding var selection: FeedKind

    var body: some View {
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }
}

import SwiftUI

struct TagView: View {
    let name: String

    @State private var details: TagDetails?
    @State private var lineType: PostLineType = .good
    @State private var store = PostListModelStore()
    @State private var updating = false

    private var auth: AuthStore { .shared }

    var body: some View {
        PostFeed(model: store.model(for: .tag(name: name, type: lineType))) {
            VStack(spacing: 0) {
                header
                Picker("Лента", selection: $lineType) {
                    ForEach([PostLineType.good, .best, .new, .all]) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                SectionSeparator()
            }
        }
        .id(lineType)
        .navigationTitle(details?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: webURL)
                    if auth.isLoggedIn, let details {
                        Button(role: details.isBlocked ? nil : .destructive) {
                            setState(details.isBlocked ? "UNSUBSCRIBED" : "BLOCKED")
                        } label: {
                            Label(details.isBlocked ? "Разблокировать тег" : "Заблокировать тег",
                                  systemImage: details.isBlocked ? "eye" : "eye.slash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if details == nil { details = try? await API.tag(name: name) }
        }
    }

    private var webURL: URL {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "https://joyreactor.cc/tag/\(encoded)") ?? URL(string: "https://joyreactor.cc")!
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                if let details, details.bigImage != nil {
                    RemoteImage(url: MediaURL.tagBanner(id: details.id), maxPixelWidth: Display.pixelWidth)
                        .frame(height: 140)
                        .clipped()
                        .overlay(LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .center, endPoint: .bottom))
                } else {
                    LinearGradient(colors: [Color.accentColor.opacity(0.35), Color(.systemBackground)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }
                AvatarView(url: details?.image != nil ? MediaURL.tagAvatar(id: details?.id ?? "") : nil, name: name, size: 84)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 4))
                    .offset(y: 42)
            }
            .padding(.bottom, 42)

            VStack(spacing: 4) {
                Text(details?.name ?? name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if let details {
                    Text("\(Formatting.compact(details.count)) постов · \(Formatting.compact(details.subscribers)) подписчиков")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            if let details {
                if auth.isLoggedIn {
                    Button {
                        setState(details.isSubscribed ? "UNSUBSCRIBED" : "SUBSCRIBED")
                    } label: {
                        Group {
                            if updating {
                                ProgressView()
                            } else {
                                Label(details.isSubscribed ? "Вы подписаны" : "Подписаться",
                                      systemImage: details.isSubscribed ? "checkmark" : "plus")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(details.isSubscribed ? Color.secondary : Color.accentColor)
                    .disabled(updating)
                }

                if let subTags = details.subTags, !subTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(subTags.filter { AppSettings.shared.showNSFW || !($0.nsfw ?? false) }) { tag in
                                TagChip(name: tag.name)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private func setState(_ state: String) {
        guard let details else { return }
        updating = true
        Task {
            defer { updating = false }
            do {
                self.details = try await API.setTagState(id: details.id, state: state)
                Haptics.tap()
            } catch {
                ToastCenter.shared.show(error)
            }
        }
    }
}

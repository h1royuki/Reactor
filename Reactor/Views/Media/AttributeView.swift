import SwiftUI

/// Renders one post/comment attribute (picture, gif, video or external embed).
struct AttributeView: View {
    let attribute: Attribute
    var maxWidth: CGFloat? = nil
    var onOpen: () -> Void = {}

    @Environment(\.openURL) private var openURL
    private var settings: AppSettings { .shared }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch attribute.kind {
        case .picture:
            mediaFrame {
                RemoteImage(url: settings.fullQualityImages ? attribute.fullImageURL : attribute.imageURL,
                            maxPixelWidth: Display.pixelWidth)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        case .gif:
            mediaFrame {
                GIFView(url: attribute.imageURL, posterURL: attribute.posterURL)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        case .video:
            mediaFrame {
                VideoAttributeView(attribute: attribute, autoplay: settings.autoplayVideo)
            }
        case .embed:
            embed
        }
    }

    private func mediaFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let width = CGFloat(max(attribute.image.width, 1))
        let limit = min(maxWidth ?? .infinity, attribute.kind == .video ? .infinity : max(width, 120))
        return Color(.secondarySystemBackground)
            .aspectRatio(attribute.image.aspectRatio, contentMode: .fit)
            .overlay { content() }
            .clipped()
            .frame(maxWidth: limit)
    }

    private var embed: some View {
        Button {
            if let url = attribute.embedURL { openURL(url) }
        } label: {
            ZStack {
                Color.black
                RemoteImage(url: attribute.embedThumbnailURL, maxPixelWidth: 1000)
                    .opacity(0.85)
                VStack(spacing: 8) {
                    Image(systemName: attribute.type == "SOUNDCLOUD" || attribute.type == "BANDCAMP" ? "music.note" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.black.opacity(0.55), in: Circle())
                    Text(attribute.embedTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: maxWidth ?? .infinity)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

struct MediaViewerState: Identifiable {
    let id = UUID()
    let attributes: [Attribute]
    let index: Int
}

/// Fullscreen pager with zoom for pictures and gifs.
struct MediaViewer: View {
    let attributes: [Attribute]
    @State var selection: Int

    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?
    @State private var preparingShare = false
    @State private var showChrome = true

    init(state: MediaViewerState) {
        attributes = state.attributes
        _selection = State(initialValue: state.index)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(attributes.enumerated()), id: \.offset) { index, attribute in
                    MediaPage(attribute: attribute)
                        .tag(index)
                        .onTapGesture { withAnimation { showChrome.toggle() } }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if showChrome {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    if attributes.count > 1 {
                        Text("\(selection + 1) / \(attributes.count)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button { share() } label: {
                        Group {
                            if preparingShare { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                        }
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(preparingShare)
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!showChrome)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func share() {
        guard attributes.indices.contains(selection) else { return }
        let attribute = attributes[selection]
        let url: URL?
        switch attribute.kind {
        case .video: url = attribute.videoURLs.first
        case .embed: url = attribute.embedURL
        default: url = attribute.fullImageURL
        }
        guard let url else { return }
        if attribute.kind == .video || attribute.kind == .embed {
            shareItem = ShareItem(url: url)
            return
        }
        preparingShare = true
        Task {
            defer { preparingShare = false }
            do {
                shareItem = ShareItem(url: try await ImagePipeline.shared.temporaryFile(for: url))
            } catch {
                ToastCenter.shared.show(error)
            }
        }
    }
}

private struct MediaPage: View {
    let attribute: Attribute

    @State private var image: UIImage?

    var body: some View {
        switch attribute.kind {
        case .picture:
            ZoomableImage(image: image)
                .overlay { if image == nil { ProgressView().tint(.white) } }
                .task {
                    if let preview = attribute.imageURL,
                       let cached = ImagePipeline.shared.cachedImage(preview, maxPixelWidth: Display.pixelWidth) {
                        image = cached
                    }
                    if let full = attribute.fullImageURL,
                       let loaded = try? await ImagePipeline.shared.image(full, maxPixelWidth: 4096) {
                        image = loaded
                    } else if image == nil, let preview = attribute.imageURL {
                        image = try? await ImagePipeline.shared.image(preview, maxPixelWidth: Display.pixelWidth)
                    }
                }
        case .gif:
            GIFView(url: attribute.imageURL, posterURL: attribute.posterURL)
                .aspectRatio(attribute.image.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .video:
            RemoteImage(url: attribute.posterURL, contentMode: .fit)
        case .embed:
            RemoteImage(url: attribute.embedThumbnailURL, contentMode: .fit)
        }
    }
}

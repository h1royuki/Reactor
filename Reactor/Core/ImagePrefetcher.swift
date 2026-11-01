import CoreGraphics
import Foundation

/// Warms the image cache for posts just below the screen, so their pictures are already decoded
/// when they scroll in. Requests mirror exactly what the feed views ask for (same URL and size),
/// otherwise the cache would miss.
@MainActor
final class ImagePrefetcher {
    static let shared = ImagePrefetcher()

    /// Posts to look ahead of the one that just appeared: generous on Wi-Fi, lighter on
    /// cellular and Low Data Mode, where posts left unseen at the end of a session cost traffic.
    static var lookahead: Int { NetworkStatus.shared.isExpensive ? 3 : 6 }
    /// The feed card shows at most this many media items before "show more".
    private static let mediaPerPost = 5

    private var requested = Set<URL>()

    func prefetch<S: Sequence>(_ posts: S) where S.Element == Post {
        let pipeline = ImagePipeline.shared
        let screenWidth = Display.pixelWidth
        let fullQuality = AppSettings.shared.fullQualityImages
        for post in posts {
            if let avatar = post.user.avatarURL { warmImage(avatar, width: 38 * 3, pipeline) }
            for attribute in post.attributes.filter(\.isMedia).prefix(Self.mediaPerPost) {
                switch attribute.kind {
                case .picture:
                    if let url = attribute.feedImageURL(fullQuality: fullQuality) { warmImage(url, width: screenWidth, pipeline) }
                case .gif:
                    if let url = attribute.imageURL { warmData(url, pipeline) }
                case .video:
                    if let url = attribute.posterURL { warmImage(url, width: screenWidth, pipeline) }
                case .embed:
                    break
                }
            }
            for attribute in post.attributes where attribute.kind == .embed {
                if let url = attribute.embedThumbnailURL { warmImage(url, width: 1000, pipeline) }
            }
        }
        if requested.count > 3000 { requested.removeAll() }
    }

    private func warmImage(_ url: URL, width: CGFloat, _ pipeline: ImagePipeline) {
        guard requested.insert(url).inserted, pipeline.cachedImage(url, maxPixelWidth: width) == nil else { return }
        Task(priority: .utility) { _ = try? await pipeline.image(url, maxPixelWidth: width) }
    }

    private func warmData(_ url: URL, _ pipeline: ImagePipeline) {
        guard requested.insert(url).inserted else { return }
        Task(priority: .utility) { _ = try? await pipeline.data(url) }
    }
}

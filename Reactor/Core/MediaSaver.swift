import Photos
import UIKit

enum MediaSaveError: LocalizedError {
    case noAccess
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .noAccess: return "Нет доступа к «Фото». Разрешите его в Настройках → Joyreactor → Фото."
        case .nothingToSave: return "В посте нет картинок или видео"
        }
    }
}

/// Saves a post's media to Photos: pictures and gifs as they are (formats Photos rejects become
/// JPEG), videos as the site's mp4 copy. A video with no mp4 yet comes back as a WebM file
/// for the share sheet, since Photos can't import WebM.
@MainActor
enum MediaSaver {
    struct Result {
        var photos = 0
        var videos = 0
        var unsavedVideo: URL?

        var summary: String? {
            var parts: [String] = []
            if photos > 0 { parts.append(photos == 1 ? "картинка" : "картинок: \(photos)") }
            if videos > 0 { parts.append(videos == 1 ? "видео" : "видео: \(videos)") }
            guard !parts.isEmpty else { return nil }
            if photos + videos == 1 { return "Сохранено в «Фото»" }
            return "Сохранено в «Фото» — " + parts.joined(separator: ", ")
        }
    }

    static func hasMedia(_ post: Post) -> Bool {
        post.attributes.contains { $0.isMedia }
    }

    static func save(_ post: Post) async throws -> Result {
        let items = post.attributes.filter { $0.isMedia }
        guard !items.isEmpty else { throw MediaSaveError.nothingToSave }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaSaveError.noAccess }

        var result = Result()
        for attribute in items {
            switch attribute.kind {
            case .picture, .gif:
                if try await savePicture(attribute) { result.photos += 1 }
            case .video:
                if let mp4 = attribute.mp4URL, let file = try? await ImagePipeline.shared.temporaryFile(for: mp4) {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: file, options: nil)
                    }
                    result.videos += 1
                } else if result.unsavedVideo == nil, let webm = attribute.webmURL {
                    result.unsavedVideo = try await ImagePipeline.shared.temporaryFile(for: webm)
                }
            case .embed:
                break
            }
        }
        return result
    }

    private static func savePicture(_ attribute: Attribute) async throws -> Bool {
        guard let url = attribute.fullImageURL else { return false }
        let original = try await ImagePipeline.shared.data(url)
        // Photos takes JPEG, PNG and GIF as they are; WebP/BMP/TIFF are re-encoded.
        let keepsFormat = ["JPEG", "PNG", "GIF"].contains(attribute.image.type)
        guard let payload = keepsFormat ? original : UIImage(data: original)?.jpegData(compressionQuality: 0.95) else {
            return false
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: payload, options: nil)
        }
        return true
    }
}

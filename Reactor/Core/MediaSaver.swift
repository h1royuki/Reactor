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

/// Saves a post's media: pictures and gifs go to Photos; WebM videos (which Photos rejects)
/// are downloaded to a file for the share sheet.
@MainActor
enum MediaSaver {
    static func photos(in post: Post) -> [Attribute] {
        post.attributes.filter { $0.kind == .picture || $0.kind == .gif }
    }

    static func video(in post: Post) -> Attribute? {
        post.attributes.first { $0.kind == .video }
    }

    static func hasMedia(_ post: Post) -> Bool {
        !photos(in: post).isEmpty || video(in: post) != nil
    }

    /// Returns how many pictures were saved.
    static func savePhotos(of post: Post) async throws -> Int {
        let items = photos(in: post)
        guard !items.isEmpty else { throw MediaSaveError.nothingToSave }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaSaveError.noAccess }

        var saved = 0
        for attribute in items {
            guard let url = attribute.fullImageURL else { continue }
            let original = try await ImagePipeline.shared.data(url)
            // Photos takes JPEG, PNG, GIF and HEIC as they are; WebP/BMP/TIFF are re-encoded.
            let keepsFormat = ["JPEG", "PNG", "GIF"].contains(attribute.image.type)
            guard let payload = keepsFormat ? original : UIImage(data: original)?.jpegData(compressionQuality: 0.95) else {
                continue
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: payload, options: nil)
            }
            saved += 1
        }
        return saved
    }

    static func videoFile(of post: Post) async throws -> URL {
        guard let url = video(in: post)?.videoURLs.first else { throw MediaSaveError.nothingToSave }
        return try await ImagePipeline.shared.temporaryFile(for: url)
    }
}

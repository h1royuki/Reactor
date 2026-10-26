import UIKit
import ImageIO

/// Downloads and decodes images off the main thread with memory + disk caching.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private let dataCache = NSCache<NSURL, NSData>()

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                                       .appendingPathComponent("media", isDirectory: true))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.httpAdditionalHeaders = ["Referer": "https://joyreactor.cc/"]
        session = URLSession(configuration: config)
        memory.totalCostLimit = 150 * 1024 * 1024
        dataCache.totalCostLimit = 40 * 1024 * 1024
    }

    var diskUsage: Int { session.configuration.urlCache?.currentDiskUsage ?? 0 }

    func clearCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
        memory.removeAllObjects()
        dataCache.removeAllObjects()
    }

    func cachedImage(_ url: URL, maxPixelWidth: CGFloat) -> UIImage? {
        memory.object(forKey: key(url, maxPixelWidth))
    }

    func data(_ url: URL) async throws -> Data {
        if let cached = dataCache.object(forKey: url as NSURL) { return cached as Data }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        if data.count < 8 * 1024 * 1024 {
            dataCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        }
        return data
    }

    /// Loads a still image, downsampled so its width is at most `maxPixelWidth`.
    func image(_ url: URL, maxPixelWidth: CGFloat) async throws -> UIImage {
        let cacheKey = key(url, maxPixelWidth)
        if let cached = memory.object(forKey: cacheKey) { return cached }
        let data = try await data(url)
        let image = try await Task.detached(priority: .userInitiated) {
            guard let image = Self.decode(data, maxPixelWidth: maxPixelWidth) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }.value
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private func key(_ url: URL, _ width: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(width))" as NSString
    }

    static func decode(_ data: Data, maxPixelWidth: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return UIImage(data: data) }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        var maxDimension = max(width, height)
        if width > maxPixelWidth, width > 0 {
            maxDimension = max(maxPixelWidth, maxPixelWidth * height / width)
        }
        // Keep extremely tall comics within texture limits.
        maxDimension = min(maxDimension, 12_000)
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxDimension),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    /// Writes the original file to a temporary location (for sharing/saving).
    func temporaryFile(for url: URL) async throws -> URL {
        let data = try await data(url)
        let name = url.lastPathComponent.isEmpty ? "image.jpeg" : url.lastPathComponent
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        return file
    }
}

import Foundation

/// Builds joyreactor CDN URLs. The slug part of a file name is ignored by the CDN,
/// only the trailing numeric attribute id and extension matter.
enum MediaURL {
    static let host = "https://img10.joyreactor.cc/pics"

    static func userAvatar(id: String) -> URL? {
        URL(string: "\(host)/avatar/user/\(NodeID.number(id))")
    }

    static func tagAvatar(id: String) -> URL? {
        URL(string: "\(host)/avatar/tag/\(NodeID.number(id))")
    }

    static func tagBanner(id: String) -> URL? {
        URL(string: "\(host)/avatar/tag/big/\(NodeID.number(id))")
    }

    static func fileExtension(_ type: String) -> String {
        switch type {
        case "PNG": return "png"
        case "GIF": return "gif"
        case "BMP": return "bmp"
        case "TIFF": return "tiff"
        case "WEBP": return "webp"
        case "MP4": return "mp4"
        case "WEBM": return "webm"
        default: return "jpeg"
        }
    }
}

extension Attribute {
    private var folder: String {
        NodeID.decode(id)?.type.hasPrefix("Comment") == true ? "comment" : "post"
    }

    private var number: String { NodeID.number(id) }

    /// Display-sized picture (server-side resized for big originals).
    var imageURL: URL? {
        URL(string: "\(MediaURL.host)/\(folder)/picture-\(number).\(MediaURL.fileExtension(image.type))")
    }

    /// Original resolution picture.
    var fullImageURL: URL? {
        URL(string: "\(MediaURL.host)/\(folder)/full/picture-\(number).\(MediaURL.fileExtension(image.type))")
    }

    /// Picture shown in feeds. The CDN's display copy is at most 811 px wide, which a phone screen
    /// (1170-1290 px) upscales; originals up to ~1300 px are barely bigger, so those load in full,
    /// larger ones use the display copy unless full quality is switched on.
    func feedImageURL(fullQuality: Bool) -> URL? {
        if fullQuality || image.width <= 1300 { return fullImageURL }
        return imageURL
    }

    /// Still frame for gifs and videos.
    var posterURL: URL? {
        URL(string: "\(MediaURL.host)/\(folder)/static/picture-\(number).jpeg")
    }

    /// H.264 copy the site makes for video gifs (may be missing on very old or just uploaded ones).
    var mp4URL: URL? {
        URL(string: "\(MediaURL.host)/\(folder)/mp4/picture-\(number).mp4")
    }

    /// Candidate video sources, best first: mp4 decodes in hardware on iOS, WebM is the fallback.
    var videoURLs: [URL] {
        var urls: [String] = [
            "\(MediaURL.host)/\(folder)/mp4/picture-\(number).mp4",
            "\(MediaURL.host)/\(folder)/webm/picture-\(number).webm",
        ]
        urls.append("\(MediaURL.host)/\(folder)/picture-\(number).\(MediaURL.fileExtension(image.type))")
        return urls.compactMap(URL.init(string:))
    }

    var webmURL: URL? {
        URL(string: "\(MediaURL.host)/\(folder)/webm/picture-\(number).webm")
    }

    /// External link for embedded players.
    var embedURL: URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http") { return URL(string: value) }
        switch type {
        case "YOUTUBE": return URL(string: "https://www.youtube.com/watch?v=\(value)")
        case "VIMEO": return URL(string: "https://vimeo.com/\(value)")
        case "COUB": return URL(string: "https://coub.com/view/\(value)")
        case "SOUNDCLOUD":
            // {"url":"https://api.soundcloud.com/tracks/<id>","height":300}
            guard let track = embedJSONURL(value) else { return nil }
            var components = URLComponents(string: "https://w.soundcloud.com/player/")
            components?.queryItems = [URLQueryItem(name: "url", value: track)]
            return components?.url
        case "BANDCAMP":
            // {"url":"album=123/size=large/bgcol=333333/linkcol=0f91ff/transparent=true/","height":1070,"width":700}
            guard let path = embedJSONURL(value) else { return nil }
            return URL(string: "https://bandcamp.com/EmbeddedPlayer/\(path)")
        default: return nil
        }
    }

    /// SoundCloud and Bandcamp embeds keep a small JSON object in `value`, not a bare id.
    private func embedJSONURL(_ value: String) -> String? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["url"] as? String
    }

    var embedThumbnailURL: URL? {
        if type == "YOUTUBE", let value { return URL(string: "https://i.ytimg.com/vi/\(value)/hqdefault.jpg") }
        return imageURL
    }

    var embedTitle: String {
        switch type {
        case "YOUTUBE": return "YouTube"
        case "VIMEO": return "Vimeo"
        case "COUB": return "Coub"
        case "SOUNDCLOUD": return "SoundCloud"
        case "BANDCAMP": return "Bandcamp"
        default: return "Видео"
        }
    }
}

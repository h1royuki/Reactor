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

    /// Still frame for gifs and videos.
    var posterURL: URL? {
        URL(string: "\(MediaURL.host)/\(folder)/static/picture-\(number).jpeg")
    }

    /// Candidate video sources, best first.
    var videoURLs: [URL] {
        var urls: [String] = ["\(MediaURL.host)/\(folder)/webm/picture-\(number).webm"]
        if image.type == "MP4" {
            urls.insert("\(MediaURL.host)/\(folder)/mp4/picture-\(number).mp4", at: 0)
            urls.append("\(MediaURL.host)/\(folder)/picture-\(number).mp4")
        } else {
            urls.append("\(MediaURL.host)/\(folder)/picture-\(number).\(MediaURL.fileExtension(image.type))")
        }
        return urls.compactMap(URL.init(string:))
    }

    /// External link for embedded players.
    var embedURL: URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http") { return URL(string: value) }
        switch type {
        case "YOUTUBE": return URL(string: "https://www.youtube.com/watch?v=\(value)")
        case "VIMEO": return URL(string: "https://vimeo.com/\(value)")
        case "COUB": return URL(string: "https://coub.com/view/\(value)")
        case "SOUNDCLOUD": return URL(string: "https://soundcloud.com/\(value)")
        case "BANDCAMP": return URL(string: "https://bandcamp.com/EmbeddedPlayer/\(value)")
        default: return nil
        }
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

import Foundation
import CoreGraphics

/// GraphQL ids are base64 of "Type:number".
enum NodeID {
    static func decode(_ id: String) -> (type: String, number: String)? {
        guard let data = Data(base64Encoded: id), let string = String(data: data, encoding: .utf8),
              let colon = string.firstIndex(of: ":") else { return nil }
        return (String(string[..<colon]), String(string[string.index(after: colon)...]))
    }

    static func number(_ id: String) -> String { decode(id)?.number ?? id }

    static func encode(type: String, number: String) -> String {
        Data("\(type):\(number)".utf8).base64EncodedString()
    }
}

struct UserRef: Decodable, Hashable, Identifiable {
    let id: String
    let username: String

    var avatarURL: URL? { MediaURL.userAvatar(id: id) }
}

struct TagRef: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let nsfw: Bool?
    let unsafe: Bool?

    var avatarURL: URL? { MediaURL.tagAvatar(id: id) }
}

struct ImageInfo: Decodable, Hashable {
    let id: String
    let width: Int
    let height: Int
    let type: String
    let hasVideo: Bool
    let comment: String?

    var aspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

struct Attribute: Decodable, Hashable, Identifiable {
    let id: String
    let type: String
    let insertId: Int?
    let image: ImageInfo
    let value: String?

    enum Kind { case picture, gif, video, embed }

    var kind: Kind {
        guard type == "PICTURE" else { return .embed }
        switch image.type {
        case "GIF": return .gif
        case "WEBM", "MP4": return .video
        default: return image.hasVideo ? .video : .picture
        }
    }

    var isMedia: Bool { kind != .embed }
}

struct VoteInfo: Decodable, Hashable {
    let power: Double
}

struct PollAnswer: Decodable, Hashable, Identifiable {
    let id: String
    let answer: String
    let count: Int
}

struct Poll: Decodable, Hashable {
    let question: String
    let answers: [PollAnswer]
    let voted: Bool
}

struct Post: Decodable, Identifiable, Hashable {
    let id: String
    let text: String
    let header: String?
    let createdAt: Date
    var rating: Double
    let commentsCount: Int
    let nsfw: Bool
    let unsafe: Bool
    var favorite: Bool
    var vote: VoteInfo?
    let user: UserRef
    let tags: [TagRef]
    let attributes: [Attribute]
    var poll: Poll?

    var number: String { NodeID.number(id) }
    var webURL: URL { URL(string: "https://joyreactor.cc/post/\(number)")! }
    var isAdult: Bool { nsfw || unsafe }

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id && lhs.rating == rhs.rating && lhs.favorite == rhs.favorite
            && lhs.vote == rhs.vote && lhs.poll == rhs.poll
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ParentRef: Decodable, Hashable {
    let id: String
}

struct Comment: Decodable, Identifiable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
    var rating: Double
    let level: Int
    let parent: ParentRef?
    let user: UserRef
    let attributes: [Attribute]
    var vote: VoteInfo?
}

struct TagDetails: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
    let subscribers: Int
    let rating: Double
    let nsfw: Bool
    let unsafe: Bool
    let image: ImageRef?
    let bigImage: ImageRef?
    let subTags: [TagRef]?
    var userTag: UserTagState?
    var favoriteTag: UserTagState?

    var subscriptionState: String? { favoriteTag?.state ?? userTag?.state }
    var isSubscribed: Bool { subscriptionState == "SUBSCRIBED" }
    var isBlocked: Bool { subscriptionState == "BLOCKED" }
}

struct ImageRef: Decodable, Hashable {
    let id: String
}

struct UserTagState: Decodable, Hashable {
    let state: String
}

struct TagSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
    let subscribers: Int
    let nsfw: Bool?
    let image: ImageRef?

    var avatarURL: URL? { image == nil ? nil : MediaURL.tagAvatar(id: id) }
}

struct UserProfile: Decodable, Identifiable, Hashable {
    let id: String
    let username: String
    let rating: Double
    let ratingWeek: Double
    let postNum: Int
    let commentNum: Int
    let createdAt: Date
    let about: String?
    let active: Bool?

    var avatarURL: URL? { MediaURL.userAvatar(id: id) }
}

enum PostLineType: String, CaseIterable, Identifiable {
    case good = "GOOD"
    case best = "BEST"
    case new = "NEW"
    case all = "ALL"
    case discussion = "DISCUSSION_ALL"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: return "Хорошее"
        case .best: return "Лучшее"
        case .new: return "Новое"
        case .all: return "Все"
        case .discussion: return "Обсуждаемое"
        }
    }

    var icon: String {
        switch self {
        case .good: return "hand.thumbsup"
        case .best: return "star"
        case .new: return "sparkles"
        case .all: return "square.stack"
        case .discussion: return "bubble.left.and.bubble.right"
        }
    }
}

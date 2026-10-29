import Foundation

enum GQL {
    static let attributeFields = """
    id type insertId image { id width height type hasVideo comment } ... on AttributeEmbed { value }
    """

    static let postFields = """
    fragment PostFields on Post {
      id text header createdAt rating commentsCount nsfw unsafe favorite
      vote { power }
      user { id username }
      tags { id name nsfw unsafe }
      attributes { \(attributeFields) }
      poll { question voted answers { id answer count } }
      bestComments {
        id text createdAt rating level
        parent { id }
        user { id username }
        vote { power }
        attributes { \(attributeFields) }
      }
    }
    """

    static let commentFields = """
    fragment CommentFields on Comment {
      id text createdAt rating level
      parent { id }
      user { id username }
      vote { power }
      attributes { \(attributeFields) }
    }
    """

    static let tagSummaryFields = "id name count subscribers nsfw image { id }"
}

/// Where a paged list of posts comes from.
enum PostSource: Hashable {
    case tag(name: String?, type: PostLineType)
    case user(username: String)
    case favorites
    case search(query: String)
    case weekTop

    var isPaged: Bool { self != .weekTop }

    /// Only the main feed and tag feeds drop viewed posts; favorites, profiles and search stay complete.
    var hidesSeen: Bool {
        if case .tag = self { return true }
        return false
    }
}

enum API {
    static var client: GraphQLClient { .shared }

    // MARK: Posts

    static func posts(_ source: PostSource, offset: Int, nsfw: Bool) async throws -> [Post] {
        switch source {
        case .tag(let name, let type):
            let q = """
            query($name: String, $type: PostLineType!, $offset: Int) {
              tag(name: $name) { postPager(type: $type) { posts(offset: $offset) { ...PostFields } } }
            }
            \(GQL.postFields)
            """
            return try await client.fetch([Post].self, q, variables: ["name": name, "type": type.rawValue, "offset": offset],
                                          path: ["tag", "postPager", "posts"])
        case .user(let username):
            let q = """
            query($u: String!, $offset: Int) {
              user(username: $u) { postPager { posts(offset: $offset) { ...PostFields } } }
            }
            \(GQL.postFields)
            """
            return try await client.fetch([Post].self, q, variables: ["u": username, "offset": offset],
                                          path: ["user", "postPager", "posts"])
        case .favorites:
            let q = """
            query($offset: Int) { me { favoritePostPager { posts(offset: $offset) { ...PostFields } } } }
            \(GQL.postFields)
            """
            do {
                return try await client.fetch([Post].self, q, variables: ["offset": offset],
                                              path: ["me", "favoritePostPager", "posts"])
            } catch APIError.notFound {
                throw APIError.unauthenticated
            }
        case .search(let query):
            let q = """
            query($q: String!, $nsfw: Boolean, $offset: Int) {
              search(query: $q, showNsfw: $nsfw, showUnsafe: $nsfw) { postPager { posts(offset: $offset) { ...PostFields } } }
            }
            \(GQL.postFields)
            """
            return try await client.fetch([Post].self, q, variables: ["q": query, "nsfw": nsfw, "offset": offset],
                                          path: ["search", "postPager", "posts"])
        case .weekTop:
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
            let q = """
            query($y: Int!, $w: Int!, $nsfw: Boolean) { weekTopPosts(year: $y, week: $w, nsfw: $nsfw) { ...PostFields } }
            \(GQL.postFields)
            """
            // The API only serves weeks that ended at least 7 days ago.
            var lastError: Error = APIError.notFound
            for weeksBack in 1...3 {
                guard let date = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: Date()) else { continue }
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                do {
                    let result = try await client.fetch([Post].self, q,
                                                        variables: ["y": c.yearForWeekOfYear ?? 2026,
                                                                    "w": c.weekOfYear ?? 1, "nsfw": nsfw],
                                                        path: ["weekTopPosts"])
                    if !result.isEmpty { return result }
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
    }

    static func postWithComments(id: String) async throws -> (Post, [Comment]) {
        let q = """
        query($id: ID!) { node(id: $id) { ... on Post { ...PostFields comments { ...CommentFields } } } }
        \(GQL.postFields)
        \(GQL.commentFields)
        """
        struct Wrapper: Decodable { let comments: [Comment] }
        let data = try await client.data(q, variables: ["id": id], path: ["node"])
        let post = try GraphQLClient.decoder.decode(Post.self, from: data)
        let comments = try GraphQLClient.decoder.decode(Wrapper.self, from: data).comments
        return (post, comments)
    }

    // MARK: Tags

    static func tag(name: String) async throws -> TagDetails {
        let q = """
        query($name: String) {
          tag(name: $name) {
            id name count subscribers rating nsfw unsafe
            image { id } bigImage { id }
            subTags { id name nsfw unsafe }
            userTag { state } favoriteTag { state }
          }
        }
        """
        return try await client.fetch(TagDetails.self, q, variables: ["name": name], path: ["tag"])
    }

    static func trends() async throws -> [TagSummary] {
        try await client.fetch([TagSummary].self, "{ trends { \(GQL.tagSummaryFields) } }", path: ["trends"])
    }

    static func topTags(nsfw: Bool) async throws -> (week: [TagSummary], all: [TagSummary]) {
        struct Top: Decodable { let week: [TagSummary]; let all: [TagSummary] }
        let q = """
        query($nsfw: Boolean) { tagTopBySubscribers(nsfw: $nsfw, limit: 30) {
          week { \(GQL.tagSummaryFields) } all { \(GQL.tagSummaryFields) } } }
        """
        let top = try await client.fetch(Top.self, q, variables: ["nsfw": nsfw], path: ["tagTopBySubscribers"])
        return (top.week, top.all)
    }

    static func autocomplete(_ mask: String) async throws -> [TagSummary] {
        let q = "query($m: String!) { tagAutocomplete(mask: $m) { \(GQL.tagSummaryFields) } }"
        return try await client.fetch([TagSummary].self, q, variables: ["m": mask], path: ["tagAutocomplete"])
    }

    static func searchTags(_ query: String, nsfw: Bool) async -> [TagSummary] {
        let q = """
        query($q: String!, $nsfw: Boolean) { search(query: $q, showNsfw: $nsfw, showUnsafe: $nsfw) { tags { \(GQL.tagSummaryFields) } } }
        """
        return (try? await client.fetch([TagSummary].self, q, variables: ["q": query, "nsfw": nsfw], path: ["search", "tags"])) ?? []
    }

    // MARK: Users

    static func user(username: String) async throws -> UserProfile {
        let q = """
        query($u: String!) { user(username: $u) { id username rating ratingWeek postNum commentNum createdAt about active } }
        """
        return try await client.fetch(UserProfile.self, q, variables: ["u": username], path: ["user"])
    }

    static func subscribedTags() async throws -> [TagSummary] {
        try await client.fetch([TagSummary].self, "{ me { subscribedTags { \(GQL.tagSummaryFields) } } }",
                               path: ["me", "subscribedTags"])
    }

    // MARK: Auth

    struct Me: Decodable {
        let id: String
        let username: String
        let token: String?
    }

    static func login(name: String, password: String) async throws -> Me {
        let q = """
        mutation($n: String!, $p: String!) { login(name: $n, password: $p) { me { id username token } } }
        """
        do {
            return try await client.fetch(Me.self, q, variables: ["n": name, "p": password], path: ["login", "me"])
        } catch APIError.unauthenticated, APIError.notFound {
            throw APIError.server("Неверный логин или пароль")
        }
    }

    static func me() async throws -> Me? {
        let payload = try await client.raw("{ me { id username } }")
        guard let me = payload["me"] as? [String: Any], let id = me["id"] as? String,
              let username = me["username"] as? String else { return nil }
        return Me(id: id, username: username, token: nil)
    }

    static func logout() async {
        _ = try? await client.raw("mutation { logout { me { id } } }")
    }

    // MARK: Actions

    struct VoteResult: Decodable {
        let rating: Double
        let vote: VoteInfo?
    }

    static func vote(id: String, plus: Bool) async throws -> VoteResult {
        let q = """
        mutation($id: ID!, $v: VoteType!) { vote(id: $id, vote: $v) {
          node(id: $id) { ... on Post { rating vote { power } } ... on Comment { rating vote { power } } } } }
        """
        return try await client.fetch(VoteResult.self, q, variables: ["id": id, "v": plus ? "PLUS" : "MINUS"],
                                      path: ["vote", "node"])
    }

    static func setFavorite(id: String, _ state: Bool) async throws -> Bool {
        struct R: Decodable { let favorite: Bool }
        let q = """
        mutation($id: ID!, $s: Boolean!) { favorite(id: $id, requestedState: $s) { node(id: $id) { ... on Post { favorite } } } }
        """
        return try await client.fetch(R.self, q, variables: ["id": id, "s": state], path: ["favorite", "node"]).favorite
    }

    static func setTagState(id: String, state: String) async throws -> TagDetails {
        let q = """
        mutation($id: ID!, $s: UserTagState!) { favoriteTag(id: $id, requestedState: $s) {
          node(id: $id) { ... on Tag {
            id name count subscribers rating nsfw unsafe
            image { id } bigImage { id }
            subTags { id name nsfw unsafe }
            userTag { state } favoriteTag { state } } } } }
        """
        return try await client.fetch(TagDetails.self, q, variables: ["id": id, "s": state], path: ["favoriteTag", "node"])
    }

    static func pollVote(answer: String, postID: String) async throws -> Poll {
        let q = """
        mutation($a: ID!, $p: ID!) { pollVote(answer: $a) { node(id: $p) { ... on Post { poll { question voted answers { id answer count } } } } } }
        """
        return try await client.fetch(Poll.self, q, variables: ["a": answer, "p": postID], path: ["pollVote", "node", "poll"])
    }

    static func comment(on id: String, text: String) async throws {
        let q = """
        mutation($id: ID!, $t: String!) { comment(id: $id, text: $t) { errorCode comment { id } } }
        """
        struct R: Decodable { let errorCode: Int; let comment: ParentRef? }
        let result = try await client.fetch(R.self, q, variables: ["id": id, "t": text], path: ["comment"])
        if result.comment == nil {
            throw APIError.server("Не удалось отправить комментарий (код \(result.errorCode))")
        }
    }
}

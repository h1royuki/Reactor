import Foundation

enum APIError: LocalizedError {
    case server(String)
    case unauthenticated
    case notFound
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .unauthenticated: return "Нужно войти в аккаунт"
        case .notFound: return "Ничего не найдено"
        case .badResponse(let code): return "Сервер ответил с ошибкой \(code)"
        }
    }
}

/// Minimal GraphQL client for https://api.joyreactor.cc/graphql.
/// Auth is a session cookie plus (when available) a bearer token from `me { token }`.
final class GraphQLClient: @unchecked Sendable {
    static let shared = GraphQLClient()

    let endpoint = URL(string: "https://api.joyreactor.cc/graphql")!
    private let session: URLSession
    private let lock = NSLock()
    private var _token: String?

    var token: String? {
        get { lock.lock(); defer { lock.unlock() }; return _token }
        set { lock.lock(); _token = newValue; lock.unlock() }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateParsing.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
        }
        return decoder
    }()

    /// Runs a query and returns the raw `data` object.
    func raw(_ query: String, variables: [String: Any?] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var vars: [String: Any] = [:]
        for (key, value) in variables { vars[key] = value ?? NSNull() }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": vars])

        let (data, response) = try await session.data(for: request)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errors = object?["errors"] as? [[String: Any]], let first = errors.first {
            let message = first["message"] as? String ?? "Ошибка сервера"
            let hasData = (object?["data"] as? [String: Any]).map { dict in
                dict.values.contains { !($0 is NSNull) }
            } ?? false
            if !hasData {
                if message.localizedCaseInsensitiveContains("unauthenticated") { throw APIError.unauthenticated }
                throw APIError.server(message)
            }
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode), object == nil {
            throw APIError.badResponse(http.statusCode)
        }
        guard let payload = object?["data"] as? [String: Any] else {
            throw APIError.server("Пустой ответ сервера")
        }
        return payload
    }

    /// Runs a query and returns the JSON found at `path` inside `data`.
    func data(_ query: String, variables: [String: Any?] = [:], path: [String]) async throws -> Data {
        let payload = try await raw(query, variables: variables)
        var current: Any = payload
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key], !(next is NSNull) else {
                throw APIError.notFound
            }
            current = next
        }
        return try JSONSerialization.data(withJSONObject: current, options: [.fragmentsAllowed])
    }

    /// Runs a query and decodes the value found at `path` inside `data`.
    func fetch<T: Decodable>(_ type: T.Type, _ query: String, variables: [String: Any?] = [:], path: [String]) async throws -> T {
        let json = try await self.data(query, variables: variables, path: path)
        return try Self.decoder.decode(T.self, from: json)
    }
}

enum DateParsing {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        iso.date(from: string) ?? isoFractional.date(from: string) ?? day.date(from: string)
    }
}

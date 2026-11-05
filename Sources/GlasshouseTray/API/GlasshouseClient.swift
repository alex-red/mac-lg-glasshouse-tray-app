import Foundation

enum GlasshouseError: LocalizedError {
    case badResponse
    case http(Int)
    case unauthorized
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: "The TV sent an unreadable response."
        case .http(let code): "The TV answered HTTP \(code)."
        case .unauthorized: "The Glasshouse token is missing or wrong."
        case .refused(let message): message
        }
    }
}

/// Talks to the Glasshouse server (`tvweb`) on the TV over its plain HTTP API.
///
/// Glasshouse has no push channel over HTTP, so callers poll `stats()` when
/// they need fresh state. Commands all go through `POST /api/control`.
final class GlasshouseClient: Sendable {
    let baseURL: URL
    private let token: String?
    private let session: URLSession

    init?(host: String, port: Int, token: String?) {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host.trimmingCharacters(in: .whitespaces)
        components.port = port
        guard let url = components.url, !(components.host ?? "").isEmpty else { return nil }
        baseURL = url
        self.token = (token?.isEmpty ?? true) ? nil : token

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 6
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    var dashboardURL: URL {
        guard let token else { return baseURL }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "k", value: token)]
        return components.url ?? baseURL
    }

    func caps() async throws -> Caps {
        try await get("/api/caps")
    }

    func stats() async throws -> Stats {
        try await get("/api/stats")
    }

    func send(_ command: Command) async throws {
        var request = request(for: "/api/control")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = command.body
        let reply: ControlReply = try await perform(request)
        if !reply.ok {
            throw GlasshouseError.refused(reply.error ?? "The TV refused “\(command.action)”.")
        }
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(request(for: path))
    }

    private func request(for path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GlasshouseError.badResponse }
        let decoder = JSONDecoder()
        switch http.statusCode {
        case 200..<300:
            guard let decoded = try? decoder.decode(T.self, from: data) else { throw GlasshouseError.badResponse }
            return decoded
        case 401:
            throw GlasshouseError.unauthorized
        default:
            // Refusals come back as {ok:false,error} with a 4xx status.
            if let reply = try? decoder.decode(ControlReply.self, from: data), let error = reply.error {
                throw GlasshouseError.refused(error)
            }
            throw GlasshouseError.http(http.statusCode)
        }
    }
}

private struct ControlReply: Decodable {
    let ok: Bool
    let error: String?
}

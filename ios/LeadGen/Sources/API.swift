import Foundation
import Security

enum APIError: LocalizedError {
    case unauthorized
    case wrongPassword
    case rateLimited
    case server(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session expired. Sign in again."
        case .wrongPassword: return "That password did not work."
        case .rateLimited: return "Too many attempts. Wait a few minutes and try again."
        case .server(let code): return "The server had a problem (\(code)). Pull to try again."
        case .network(let message): return message
        }
    }
}

private struct TokenReply: Decodable { var token: String? }

struct APIClient {
    static let baseURL = URL(string: "https://leadgen-admin-alpha.vercel.app")!
    static let webAdminURL = URL(string: "https://leadgen-admin-alpha.vercel.app/m")!

    var token: String?

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()

    func login(password: String) async throws -> String {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent("api/m/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        let (data, code) = try await send(req)
        switch code {
        case 200:
            guard let t = try? JSONDecoder().decode(TokenReply.self, from: data).token, !t.isEmpty else {
                throw APIError.server(code)
            }
            return t
        case 401: throw APIError.wrongPassword
        case 429: throw APIError.rateLimited
        default: throw APIError.server(code)
        }
    }

    func get(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.server(0) }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, code) = try await send(req)
        switch code {
        case 200: return data
        case 401: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.server(code)
        }
    }

    private func send(_ req: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, resp) = try await Self.session.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.network("You are offline. Showing the last saved data.")
            case .timedOut:
                throw APIError.network("The server took too long to answer.")
            default:
                throw APIError.network(e.localizedDescription)
            }
        }
    }
}

enum Endpoint {
    static func path(_ path: String, _ items: [URLQueryItem] = []) -> String {
        guard var components = URLComponents(string: path) else { return path }
        if !items.isEmpty { components.queryItems = items }
        return components.string ?? path
    }
}

// MARK: Keychain

enum Keychain {
    private static let service = "com.antonzarwel.leadgenadmin"
    private static let account = "admin-token"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        delete()
        var q = base
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

// MARK: Disk cache (last good response per endpoint, so the app opens instantly)

enum DiskCache {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("api", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func save(_ data: Data, as name: String) {
        try? data.write(to: dir.appendingPathComponent(name + ".json"), options: [.atomic, .completeFileProtection])
    }

    static func load(_ name: String) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(name + ".json"))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: dir)
    }
}

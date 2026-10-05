import Foundation

public enum SyncError: LocalizedError {
    case invalidURL, unauthorized, server(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter an HTTPS Convex HTTP URL ending in .convex.site."
        case .unauthorized: return "The sync key was rejected. Check your connection settings."
        case .server(let code): return "Sync could not finish (HTTP \(code)). Your time is saved on this Mac."
        }
    }
}

public struct SyncClient: Sendable {
    public let endpoint: URL
    public let token: String
    public init(baseURL: String, token: String) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", let host = url.host, host.hasSuffix(".convex.site"), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.port == nil, url.path.isEmpty || url.path == "/", !token.isEmpty else { throw SyncError.invalidURL }
        endpoint = url.appendingPathComponent("sync"); self.token = token
    }
    public func send(_ request: SyncRequest) async throws -> SyncResponse {
        var req = URLRequest(url: endpoint, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        // Never forward a bearer key to a redirect destination.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.server(0) }
        guard http.statusCode != 401 else { throw SyncError.unauthorized }
        guard http.statusCode == 200 else { throw SyncError.server(http.statusCode) }
        return try JSONDecoder().decode(SyncResponse.self, from: data)
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

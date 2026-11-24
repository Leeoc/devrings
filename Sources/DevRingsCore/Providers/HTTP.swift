import Foundation

public enum ProviderError: LocalizedError, Equatable {
    case unauthorized(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized(let provider): "\(provider) didn't accept your credentials."
        case .http(let status, let provider): "\(provider) returned an error (\(status))."
        }
    }
}

struct HTTP: Sendable {
    let provider: String
    let headers: [String: String]

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        try await send(URLRequest(url: url))
    }

    func post(_ url: URL, json: [String: any Sendable]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await send(request).0
    }

    func post(_ url: URL, form: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which a form body would read as a space.
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return try await send(request).0
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw ProviderError.unauthorized(provider) }
        guard (200..<300).contains(status), let http = response as? HTTPURLResponse else {
            throw ProviderError.http(status, provider)
        }
        return (data, http)
    }
}

extension JSONDecoder {
    /// GitLab timestamps come with and without fractional seconds.
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = (try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date(s, strategy: .iso8601)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Bad date \(s)"))
        }
        return decoder
    }()
}

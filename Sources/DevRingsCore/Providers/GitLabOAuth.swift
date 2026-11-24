import CryptoKit
import Foundation

/// Sign in with GitLab using OAuth with PKCE, so the app never holds a client secret.
public enum GitLabOAuth {
    /// The DevRings application on gitlab.com, registered as non-confidential. Public by design.
    public static let clientID = "bee6be94c736712ab2eca58ddd549d40f5df18a43c693e9cbe91f7a2c330348c"
    public static let host = URL(string: "https://gitlab.com")!
    public static let callbackScheme = "devrings"
    public static let redirectURI = "devrings://oauth"
    static let scope = "read_api"

    public static var isConfigured: Bool { !clientID.isEmpty }

    public struct Request: Sendable {
        public let url: URL
        let verifier: String
        let state: String
    }

    public static func request(verifier: String = random(), state: String = random()) -> Request {
        let url = host.appending(path: "oauth/authorize").appending(queryItems: [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ])
        return Request(url: url, verifier: verifier, state: state)
    }

    /// Exchanges the code GitLab sent back to `redirectURI` for tokens.
    public static func signIn(_ request: Request, callback: URL) async throws -> GitLabCredentials {
        let code = try code(from: callback, state: request.state)
        let data = try await HTTP(provider: "GitLab", headers: [:]).post(host.appending(path: "oauth/token"), form: [
            "grant_type": "authorization_code", "client_id": clientID, "code": code,
            "redirect_uri": redirectURI, "code_verifier": request.verifier,
        ])
        var credentials = try credentials(from: data)
        credentials.codeVerifier = request.verifier
        return credentials
    }

    /// GitLab rotates refresh tokens, so the result must replace what's stored.
    static func refresh(_ credentials: GitLabCredentials) async throws -> GitLabCredentials {
        guard let refreshToken = credentials.refreshToken else { throw ProviderError.unauthorized("GitLab") }
        var form = ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": refreshToken, "redirect_uri": redirectURI]
        form["code_verifier"] = credentials.codeVerifier
        let data = try await HTTP(provider: "GitLab", headers: [:]).post(credentials.host.appending(path: "oauth/token"), form: form)
        var refreshed = try Self.credentials(from: data, host: credentials.host)
        refreshed.codeVerifier = credentials.codeVerifier
        return refreshed
    }

    public static func revoke(_ credentials: GitLabCredentials) async {
        guard credentials.isOAuth else { return }
        _ = try? await HTTP(provider: "GitLab", headers: [:]).post(credentials.host.appending(path: "oauth/revoke"),
                                                                   form: ["client_id": clientID, "token": credentials.token])
    }

    // MARK: Pieces, kept separate so they can be tested

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func code(from callback: URL, state: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw SignInError.denied(value("error_description") ?? error) }
        guard value("state") == state else { throw SignInError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw SignInError.missingCode }
        return code
    }

    static func credentials(from data: Data, host: URL = host) throws -> GitLabCredentials {
        struct Token: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let created_at: Double?
        }
        let token = try JSONDecoder().decode(Token.self, from: data)
        let issued = token.created_at.map(Date.init(timeIntervalSince1970:)) ?? .now
        return GitLabCredentials(host: host, token: token.access_token, refreshToken: token.refresh_token,
                                 expiresAt: token.expires_in.map { issued.addingTimeInterval($0) })
    }

    public static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum SignInError: LocalizedError, Equatable {
    case denied(String)
    case stateMismatch
    case missingCode

    public var errorDescription: String? {
        switch self {
        case .denied(let reason): "GitLab didn't allow the sign-in: \(reason)"
        case .stateMismatch, .missingCode: "The sign-in didn't complete. Try again."
        }
    }
}

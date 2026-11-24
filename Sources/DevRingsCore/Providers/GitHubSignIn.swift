import Foundation

/// Sign in with GitHub using the device flow: show a code, the person approves it on github.com,
/// and the app polls for the token. It needs no client secret, so it suits an open-source desktop app.
public enum GitHubSignIn {
    /// The DevRings OAuth App on github.com, with device flow enabled. Public by design.
    public static let clientID = "Ov23li9e8wZrIaGuj2aw"
    /// Reading pull requests and reviews in private repositories needs `repo`; GitHub has no read-only scope for it.
    static let scope = "repo"
    static let host = URL(string: "https://github.com")!

    public static var isConfigured: Bool { !clientID.isEmpty }

    public struct Code: Sendable, Equatable {
        public let userCode: String
        public let verificationURI: URL
        let deviceCode: String
        let interval: Int
        let expiresIn: Int
    }

    public static func start() async throws -> Code {
        let data = try await HTTP(provider: "GitHub", headers: [:])
            .post(host.appending(path: "login/device/code"), form: ["client_id": clientID, "scope": scope])
        return try code(from: data)
    }

    /// Polls until the code is approved, denied or expires. Cancelling the task stops it.
    public static func waitForApproval(_ code: Code) async throws -> GitHubCredentials {
        var interval = code.interval
        let deadline = Date.now.addingTimeInterval(TimeInterval(code.expiresIn))
        while Date.now < deadline {
            try await Task.sleep(for: .seconds(interval))
            let data = try await HTTP(provider: "GitHub", headers: [:]).post(host.appending(path: "login/oauth/access_token"), form: [
                "client_id": clientID, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            switch try poll(data) {
            case .token(let token): return GitHubCredentials(token: token, signedIn: true)
            case .pending: continue
            case .slowDown(let newInterval): interval = newInterval ?? interval + 5
            }
        }
        throw GitHubSignInError.expired
    }

    // MARK: Pieces, kept separate so they can be tested

    enum Poll: Equatable {
        case pending
        case slowDown(Int?)
        case token(String)
    }

    static func code(from data: Data) throws -> Code {
        struct Response: Decodable {
            let device_code: String
            let user_code: String
            let verification_uri: URL
            let expires_in: Int
            let interval: Int
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return Code(userCode: r.user_code, verificationURI: r.verification_uri, deviceCode: r.device_code,
                    interval: r.interval, expiresIn: r.expires_in)
    }

    static func poll(_ data: Data) throws -> Poll {
        struct Response: Decodable {
            let access_token: String?
            let error: String?
            let error_description: String?
            let interval: Int?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        if let token = r.access_token { return .token(token) }
        switch r.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(r.interval)
        case "access_denied": throw GitHubSignInError.denied
        case "expired_token": throw GitHubSignInError.expired
        default: throw GitHubSignInError.failed(r.error_description ?? r.error ?? "no token")
        }
    }
}

public enum GitHubSignInError: LocalizedError, Equatable {
    case denied
    case expired
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .denied: "The sign-in was cancelled on GitHub."
        case .expired: "The code expired before it was approved. Try again."
        case .failed(let reason): "GitHub sign-in didn't complete: \(reason)"
        }
    }
}

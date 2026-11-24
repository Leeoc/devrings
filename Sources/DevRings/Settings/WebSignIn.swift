import AppKit
import AuthenticationServices

/// The system's secure sign-in sheet: it shares your browser's cookies, so if you're already signed in to
/// GitLab it's one click, and the page can't be read by this app.
@MainActor
final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func callback(for url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // AuthenticationServices calls back on a background queue. Without @Sendable the closure would be
            // treated as main-actor code and Swift's isolation check would trap.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { @Sendable callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(throwing: CancellationError()) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor() }
    }

    /// True when the person closed the sheet themselves, which isn't an error worth showing.
    static func wasCancelled(_ error: any Error) -> Bool {
        error is CancellationError || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}

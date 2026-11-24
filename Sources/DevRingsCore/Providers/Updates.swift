import Foundation

public struct AvailableUpdate: Equatable, Sendable {
    public let version: String
    public let page: URL
}

/// Asks GitHub for the latest release. It never downloads or installs anything.
public enum Updates {
    static let latestRelease = URL(string: "https://api.github.com/repos/Leeoc/devrings/releases/latest")!

    public static func check(current: String) async throws -> AvailableUpdate? {
        let data = try await HTTP(provider: "GitHub", headers: [:]).get(latestRelease).0
        return try update(from: data, current: current)
    }

    static func update(from data: Data, current: String) throws -> AvailableUpdate? {
        struct Release: Decodable { let tag_name: String; let html_url: URL; let draft: Bool?; let prerelease: Bool? }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard release.draft != true, release.prerelease != true else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return isNewer(version, than: current) ? AvailableUpdate(version: version, page: release.html_url) : nil
    }

    static func isNewer(_ version: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let (a, b) = (parts(version), parts(current))
        for i in 0..<max(a.count, b.count) where a[safe: i] != b[safe: i] {
            return a[safe: i] > b[safe: i]
        }
        return false
    }
}

private extension Array where Element == Int {
    subscript(safe i: Int) -> Int { indices.contains(i) ? self[i] : 0 }
}

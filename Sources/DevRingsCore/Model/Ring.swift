import Foundation

public enum RingID: Codable, Hashable, Sendable {
    case ship, review, ticket(UUID)
}

public struct RingItem: Codable, Hashable, Sendable {
    public var ref: String
    public var title: String
    public var url: URL
    /// Project path for MRs and PRs, project name for tickets.
    public var project: String?
    /// When it merged, or when you first reviewed it that day.
    public var date: Date?
    /// The ticket's status after the move.
    public var status: String?

    public init(ref: String, title: String, url: URL, project: String? = nil, date: Date? = nil, status: String? = nil) {
        self.ref = ref
        self.title = title
        self.url = url
        self.project = project
        self.date = date
        self.status = status
    }

    /// `!123` for MRs, `#123` for PRs, the key for tickets.
    public var shortRef: String {
        ref.lastIndex { $0 == "!" || $0 == "#" }.map { String(ref[$0...]) } ?? ref
    }
}

extension RingItem {
    /// The title without a leading gitmoji shortcode, and without leading ticket keys the UI already shows
    /// as links. "Draft:" and a leading emoji stay.
    public func displayTitle(hiding keys: [String]) -> String {
        var rest = Substring(title)
        var kept = ""
        if rest.hasPrefix("Draft: ") {
            kept += "Draft: "
            rest = rest.dropFirst(7)
        }
        if let match = rest.prefixMatch(of: /:[a-z0-9_+-]+: */) {
            rest = rest[match.range.upperBound...]
        } else if let first = rest.first, first.unicodeScalars.first?.properties.isEmojiPresentation == true {
            kept += String(first)
            rest = rest.dropFirst().drop { $0 == " " }
            kept += " "
        }
        var stripped = true
        while stripped {
            stripped = false
            for key in keys {
                for form in ["(\(key)) ", "(\(key))", "\(key): ", "\(key) "] where rest.hasPrefix(form) {
                    rest = rest.dropFirst(form.count)
                    stripped = true
                }
            }
        }
        let result = (kept + rest).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? title : result
    }
}

public enum TicketKeys {
    /// Jira-style keys mentioned in `text`, first mention first. `projects` limits them to known
    /// project keys, so things like UTF-8 don't count.
    public static func find(in text: String, projects: Set<String>? = nil) -> [String] {
        var seen = Set<String>()
        return text.matches(of: /\b([A-Z][A-Z0-9]{1,9})-[0-9]+\b/).compactMap { match in
            let key = String(match.output.0)
            guard projects?.contains(String(match.output.1)) ?? true, seen.insert(key).inserted else { return nil }
            return key
        }
    }
}

public struct RingResult: Codable, Hashable, Sendable, Identifiable {
    public var id: RingID
    public var name: String
    public var goal: Int
    public var items: [RingItem]

    public init(id: RingID, name: String, goal: Int, items: [RingItem]) {
        self.id = id
        self.name = name
        self.goal = goal
        self.items = items
    }

    public var count: Int { items.count }
    public var progress: Double { Double(count) / Double(max(goal, 1)) }
    public var isClosed: Bool { count >= goal }
}

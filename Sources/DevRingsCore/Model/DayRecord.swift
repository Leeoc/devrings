import Foundation

public enum PauseReason: String, Codable, Sendable {
    case manual, range, calendar, noActivity
}

public struct DayRecord: Codable, Hashable, Sendable {
    /// Local calendar day as `yyyy-MM-dd`, so records sort and key by string.
    public var date: String
    public var rings: [RingResult]
    public var pause: PauseReason?

    public init(date: String, rings: [RingResult], pause: PauseReason? = nil) {
        self.date = date
        self.rings = rings
        self.pause = pause
    }

    public var isPerfect: Bool { pause == nil && !rings.isEmpty && rings.allSatisfy(\.isClosed) }
}

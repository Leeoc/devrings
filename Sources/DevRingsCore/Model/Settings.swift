import Foundation

public struct PauseRange: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var start: String
    public var end: String

    public init(start: String, end: String) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public func contains(_ day: String) -> Bool { start <= day && day <= end }
}

public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    /// The ring colours, as in Fitness.
    case colour
    /// One tone that macOS tints to match the other menu bar icons.
    case monochrome
    /// Grey until a ring closes, then its colour.
    case greyUntilClosed
}

public struct Settings: Codable, Hashable, Sendable {
    public var setup = RingSetup()
    /// `Calendar` weekday numbers, 1 = Sunday.
    public var workingDays: Set<Int> = [2, 3, 4, 5, 6]
    public var pauseRanges: [PauseRange] = []
    public var autoPauseIdleDays = true
    public var calendarKeyword = "OOO"
    public var recapHour = 8
    public var recapMinute = 30
    public var menuBarStyle = MenuBarStyle.colour
    /// Shows how many rings are closed, like "2/3", beside the menu bar icon.
    public var menuBarShowsCount = false

    public init() {}

    // Every key is optional so a settings file from an older build still loads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        setup = try c.decodeIfPresent(RingSetup.self, forKey: .setup) ?? d.setup
        workingDays = try c.decodeIfPresent(Set<Int>.self, forKey: .workingDays) ?? d.workingDays
        pauseRanges = try c.decodeIfPresent([PauseRange].self, forKey: .pauseRanges) ?? d.pauseRanges
        autoPauseIdleDays = try c.decodeIfPresent(Bool.self, forKey: .autoPauseIdleDays) ?? d.autoPauseIdleDays
        calendarKeyword = try c.decodeIfPresent(String.self, forKey: .calendarKeyword) ?? d.calendarKeyword
        recapHour = try c.decodeIfPresent(Int.self, forKey: .recapHour) ?? d.recapHour
        recapMinute = try c.decodeIfPresent(Int.self, forKey: .recapMinute) ?? d.recapMinute
        menuBarStyle = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? d.menuBarStyle
        menuBarShowsCount = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsCount) ?? d.menuBarShowsCount
    }
}

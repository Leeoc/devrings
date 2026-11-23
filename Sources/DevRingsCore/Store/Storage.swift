import Foundation

public enum Storage {
    public static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "DevRings")

    /// A file that exists but won't decode is moved aside rather than left to be overwritten.
    public static func load<T: Decodable>(_ type: T.Type, from name: String, in directory: URL = directory) -> T? {
        let url = directory.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let aside = directory.appending(path: "\(name).unreadable-\(Int(Date.now.timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public static func save(_ value: some Encodable, to name: String, in directory: URL = directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: directory.appending(path: name), options: .atomic)
    }
}

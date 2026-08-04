import Foundation

struct PersistedWorkspace: Codable {
    var cases: [SignalCase]
    var events: [LogEvent]
    var configuration: ProviderConfiguration
    var projectPath: String?

    static let empty = PersistedWorkspace(cases: [], events: [], configuration: .empty, projectPath: nil)
}

enum WorkspaceStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Signalcase", isDirectory: true).appendingPathComponent("workspace.json")
    }

    static func load() -> PersistedWorkspace {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PersistedWorkspace.self, from: data)) ?? .empty
    }

    static func save(_ workspace: PersistedWorkspace) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workspace)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum DateParser {
    static func parse(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let seconds = value as? Double { return dateFromNumber(seconds) }
        if let seconds = value as? Int { return dateFromNumber(Double(seconds)) }
        guard let string = value as? String else { return nil }

        if let number = Double(string) { return dateFromNumber(number) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func dateFromNumber(_ number: Double) -> Date {
        Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
    }
}


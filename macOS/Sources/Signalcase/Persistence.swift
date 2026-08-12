import Foundation

struct PersistedWorkspace: Codable {
    var cases: [SignalCase]
    var events: [LogEvent]
    var configuration: ProviderConfiguration
    var cloudProjectID: UUID?
    var lastSyncReport: SyncReport?
    var ignoredFingerprints: [IgnoredFingerprint]
    var deletedCases: [SignalCase]
    var hasCompletedOnboarding: Bool
    var automaticSyncEnabled: Bool
    var automaticSyncIntervalMinutes: Int
    var lastSuccessfulSyncBySource: [String: Date]
    var processedWebhookIDs: [String]

    init(
        cases: [SignalCase],
        events: [LogEvent],
        configuration: ProviderConfiguration,
        cloudProjectID: UUID? = nil,
        lastSyncReport: SyncReport? = nil,
        ignoredFingerprints: [IgnoredFingerprint] = [],
        deletedCases: [SignalCase] = [],
        hasCompletedOnboarding: Bool = false,
        automaticSyncEnabled: Bool = false,
        automaticSyncIntervalMinutes: Int = 5,
        lastSuccessfulSyncBySource: [String: Date] = [:],
        processedWebhookIDs: [String] = []
    ) {
        self.cases = cases
        self.events = events
        self.configuration = configuration
        self.cloudProjectID = cloudProjectID
        self.lastSyncReport = lastSyncReport
        self.ignoredFingerprints = ignoredFingerprints
        self.deletedCases = deletedCases
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.automaticSyncEnabled = automaticSyncEnabled
        self.automaticSyncIntervalMinutes = automaticSyncIntervalMinutes
        self.lastSuccessfulSyncBySource = lastSuccessfulSyncBySource
        self.processedWebhookIDs = processedWebhookIDs
    }

    private enum CodingKeys: String, CodingKey {
        case cases, events, configuration, cloudProjectID, lastSyncReport, ignoredFingerprints, deletedCases, hasCompletedOnboarding
        case automaticSyncEnabled, automaticSyncIntervalMinutes, lastSuccessfulSyncBySource
        case processedWebhookIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cases = try values.decodeIfPresent([SignalCase].self, forKey: .cases) ?? []
        events = try values.decodeIfPresent([LogEvent].self, forKey: .events) ?? []
        configuration = try values.decodeIfPresent(ProviderConfiguration.self, forKey: .configuration) ?? .empty
        cloudProjectID = try values.decodeIfPresent(UUID.self, forKey: .cloudProjectID)
        lastSyncReport = try values.decodeIfPresent(SyncReport.self, forKey: .lastSyncReport)
        ignoredFingerprints = try values.decodeIfPresent([IgnoredFingerprint].self, forKey: .ignoredFingerprints) ?? []
        deletedCases = try values.decodeIfPresent([SignalCase].self, forKey: .deletedCases) ?? []
        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        automaticSyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .automaticSyncEnabled) ?? false
        automaticSyncIntervalMinutes = max(5, try values.decodeIfPresent(Int.self, forKey: .automaticSyncIntervalMinutes) ?? 5)
        lastSuccessfulSyncBySource = try values.decodeIfPresent([String: Date].self, forKey: .lastSuccessfulSyncBySource) ?? [:]
        processedWebhookIDs = try values.decodeIfPresent([String].self, forKey: .processedWebhookIDs) ?? []
    }

    static let empty = PersistedWorkspace(cases: [], events: [], configuration: .empty)
}

enum WorkspaceStore {
    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Signalcase", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("workspace.json")
    }

    private static func projectFileURL(_ projectID: UUID) -> URL {
        directoryURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("(projectID.uuidString.lowercased()).json")
    }

    static func load() -> PersistedWorkspace {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PersistedWorkspace.self, from: data)) ?? .empty
    }

    static func load(projectID: UUID) -> PersistedWorkspace {
        let url = projectFileURL(projectID)
        guard let data = try? Data(contentsOf: url) else {
            var workspace = PersistedWorkspace.empty
            workspace.cloudProjectID = projectID
            workspace.hasCompletedOnboarding = true
            return workspace
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var workspace = (try? decoder.decode(PersistedWorkspace.self, from: data)) ?? .empty
        workspace.cloudProjectID = projectID
        return workspace
    }

    static func save(_ workspace: PersistedWorkspace) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workspace)
        try data.write(to: fileURL, options: .atomic)
        if let projectID = workspace.cloudProjectID {
            let projectURL = projectFileURL(projectID)
            try FileManager.default.createDirectory(
                at: projectURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: projectURL, options: .atomic)
        }
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

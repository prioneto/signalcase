import Foundation

enum CaseStatus: String, CaseIterable, Codable, Identifiable {
    case new
    case triaged
    case fixing
    case verified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .triaged: "Reviewed"
        case .fixing: "Fixing"
        case .verified: "Verified"
        }
    }

    var explanation: String {
        switch self {
        case .new: "Detected and waiting for someone to review the evidence."
        case .triaged: "Confirmed as a real problem and ready for a developer."
        case .fixing: "A developer is actively working on the problem."
        case .verified: "The fix was checked and the problem no longer reproduces."
        }
    }

    var advanceActionTitle: String? {
        switch self {
        case .new: "Mark as reviewed"
        case .triaged: "Start fixing"
        case .fixing: "Mark as verified"
        case .verified: nil
        }
    }

    var next: CaseStatus? {
        switch self {
        case .new: .triaged
        case .triaged: .fixing
        case .fixing: .verified
        case .verified: nil
        }
    }
}

enum CaseSeverity: String, Codable {
    case critical
    case high
    case normal

    var title: String { rawValue.uppercased() }
}

enum CaseFilter: String, CaseIterable, Identifiable {
    case all
    case new
    case triaged
    case fixing
    case verified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All cases"
        case .new: "New"
        case .triaged: "Reviewed"
        case .fixing: "Fixing"
        case .verified: "Verified"
        }
    }

    var status: CaseStatus? { CaseStatus(rawValue: rawValue) }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case connections
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .connections: "Connections"
        case .activity: "Activity & data"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .activity: "checklist.unchecked"
        }
    }
}

enum LogSource: String, CaseIterable, Codable, Identifiable, Hashable {
    case supabase
    case stripe
    case render
    case revenueCat
    case sentry
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supabase: "Supabase"
        case .stripe: "Stripe"
        case .render: "Render"
        case .revenueCat: "RevenueCat"
        case .sentry: "Sentry"
        case .application: "Application"
        }
    }

    var shortTitle: String {
        switch self {
        case .supabase: "SB"
        case .stripe: "ST"
        case .render: "RD"
        case .revenueCat: "RC"
        case .sentry: "SN"
        case .application: "APP"
        }
    }

    var systemImage: String {
        switch self {
        case .supabase: "cylinder.split.1x2.fill"
        case .stripe: "creditcard.fill"
        case .render: "server.rack"
        case .revenueCat: "crown.fill"
        case .sentry: "waveform.path.ecg"
        case .application: "terminal.fill"
        }
    }
}

enum EventLevel: String, Codable {
    case info
    case warning
    case error
    case deploy
    case success
}

enum CorrelationKind: String, Codable {
    case exactID
    case providerGroup
    case fingerprint
    case timeWindow
    case standalone

    var title: String {
        switch self {
        case .exactID: "Exact ID match"
        case .providerGroup: "Provider grouping"
        case .fingerprint: "Error fingerprint"
        case .timeWindow: "Time matched"
        case .standalone: "Standalone event"
        }
    }

    var isProven: Bool {
        self == .exactID || self == .providerGroup
    }
}

struct LogEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: LogSource
    let level: EventLevel
    let title: String
    let detail: String
    let requestID: String?
    let externalID: String?
    let userID: String?
    let release: String?
    let route: String?
    let fingerprint: String
    let correlation: CorrelationKind
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date,
        source: LogSource,
        level: EventLevel,
        title: String,
        detail: String,
        requestID: String? = nil,
        externalID: String? = nil,
        userID: String? = nil,
        release: String? = nil,
        route: String? = nil,
        fingerprint: String? = nil,
        correlation: CorrelationKind = .standalone,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.title = title
        self.detail = detail
        self.requestID = requestID
        self.externalID = externalID
        self.userID = userID
        self.release = release
        self.route = route
        self.fingerprint = fingerprint ?? EventFingerprint.make(source: source, message: "\(title) \(detail)")
        self.correlation = correlation
        self.metadata = metadata
    }
}

enum FindingTone: String, Codable {
    case good
    case warning
    case failure
    case neutral
}

struct CaseFinding: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let detail: String
    let tone: FindingTone

    init(id: UUID = UUID(), title: String, detail: String, tone: FindingTone) {
        self.id = id
        self.title = title
        self.detail = detail
        self.tone = tone
    }
}

struct CodeReference: Identifiable, Codable, Hashable {
    var id: String { "\(path):\(line)" }
    let path: String
    let line: Int
    let reason: String
}

struct SignalCase: Identifiable, Codable, Hashable {
    let id: UUID
    var reference: String
    var title: String
    var summary: String
    var status: CaseStatus
    var severity: CaseSeverity
    var occurrenceCount: Int
    var affectedUsers: Int
    var firstSeen: Date
    var lastSeen: Date
    var release: String
    var environment: String
    var fingerprint: String
    var events: [LogEvent]
    var findings: [CaseFinding]
    var codeReferences: [CodeReference]
    var reproduction: [String]
    var detectionNote: String = ""

    var sources: [LogSource] {
        Array(Set(events.map(\.source))).sorted { $0.rawValue < $1.rawValue }
    }
}

enum EventDisposition: String, Codable, CaseIterable, Identifiable {
    case failure
    case routine
    case unsupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .failure: "Failures"
        case .routine: "Routine ignored"
        case .unsupported: "Unsupported"
        }
    }
}

struct EventDiagnostic: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: LogSource
    let disposition: EventDisposition
    let title: String
    let detail: String
    let reason: String
    let fingerprint: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: LogSource,
        disposition: EventDisposition,
        title: String,
        detail: String,
        reason: String,
        fingerprint: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.disposition = disposition
        self.title = title
        self.detail = detail
        self.reason = reason
        self.fingerprint = fingerprint
    }
}

struct SyncReport: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let sources: [LogSource]
    let diagnostics: [EventDiagnostic]
    let sourceErrors: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sources: [LogSource],
        diagnostics: [EventDiagnostic],
        sourceErrors: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sources = sources
        self.diagnostics = diagnostics
        self.sourceErrors = sourceErrors
    }

    var checkedCount: Int { diagnostics.count }
    var failureCount: Int { diagnostics.filter { $0.disposition == .failure }.count }
    var routineCount: Int { diagnostics.filter { $0.disposition == .routine }.count }
    var unsupportedCount: Int { diagnostics.filter { $0.disposition == .unsupported }.count }

    var summary: String {
        let checked = checkedCount == 1 ? "event" : "events"
        let failures = failureCount == 1 ? "failure" : "failures"
        let routine = routineCount == 1 ? "routine event" : "routine events"
        return "\(checkedCount) \(checked) checked, \(failureCount) \(failures), \(routineCount) \(routine) ignored, \(unsupportedCount) unsupported"
    }
}

struct IgnoredFingerprint: Identifiable, Codable, Hashable {
    var id: String { fingerprint }
    let fingerprint: String
    let title: String
    let ignoredAt: Date
}

enum IntegrationState: String, Codable {
    case connected
    case available
    case disconnected
    case waitingForEvent
    case syncing
    case failed
}

struct Integration: Identifiable, Codable, Hashable {
    let source: LogSource
    var state: IntegrationState
    let detail: String
    var lastSync: Date? = nil
    var eventCount: Int = 0
    var errorMessage: String? = nil

    var id: String { source.id }
}

struct ProviderConfiguration: Codable, Hashable {
    var supabaseProjectRef = ""
    var sentryOrganization = ""
    var sentryProject = ""
    var sentryBaseURL = "https://sentry.io"
    var renderOwnerID = ""
    var renderResourceIDs = ""
    var revenueCatPort = 9782

    static let empty = ProviderConfiguration()
}

enum EventFingerprint {
    static func make(source: LogSource, message: String) -> String {
        let normalized = message
            .lowercased()
            .replacingOccurrences(of: #"[0-9a-f]{8}-[0-9a-f-]{27,}"#, with: "<id>", options: .regularExpression)
            .replacingOccurrences(of: #"\b(req|evt|cus|sub|usr|job|dep|pi|ch)_[a-zA-Z0-9_-]+\b"#, with: "<id>", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, with: "<ip>", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\b"#, with: "<n>", options: .regularExpression)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return "\(source.rawValue):\(normalized)"
    }
}

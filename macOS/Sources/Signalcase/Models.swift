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
        case .triaged: "Triaged"
        case .fixing: "Fixing"
        case .verified: "Verified"
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
        case .triaged: "Triaged"
        case .fixing: "Fixing"
        case .verified: "Verified"
        }
    }

    var status: CaseStatus? { CaseStatus(rawValue: rawValue) }
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

struct LogEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: LogSource
    let level: EventLevel
    let title: String
    let detail: String
    let requestID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        source: LogSource,
        level: EventLevel,
        title: String,
        detail: String,
        requestID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.title = title
        self.detail = detail
        self.requestID = requestID
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

    var sources: [LogSource] {
        Array(Set(events.map(\.source))).sorted { $0.rawValue < $1.rawValue }
    }
}

enum IntegrationState: String, Codable {
    case connected
    case demo
    case available
}

struct Integration: Identifiable, Codable, Hashable {
    let source: LogSource
    var state: IntegrationState
    let detail: String

    var id: String { source.id }
}

enum EventFingerprint {
    static func make(source: LogSource, message: String) -> String {
        let normalized = message
            .lowercased()
            .replacingOccurrences(of: #"[0-9a-f]{8}-[0-9a-f-]{27,}"#, with: "<id>", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\b"#, with: "<n>", options: .regularExpression)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return "\(source.rawValue):\(normalized)"
    }
}


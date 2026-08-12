import Foundation

struct DetectionResult {
    let cases: [SignalCase]
    let candidateCount: Int
    let ignoredCount: Int
}

enum SignalDetector {
    static func syncReport(
        events: [LogEvent],
        unsupported: [EventDiagnostic],
        ignoredFingerprints: Set<String>,
        sources: Set<LogSource>,
        suppressedEventKeys: Set<String> = [],
        sourceErrors: [String] = []
    ) -> SyncReport {
        let diagnostics = events.map { event -> EventDiagnostic in
            if suppressedEventKeys.contains(diagnosticEventKey(event)) {
                return diagnostic(
                    for: event,
                    disposition: .routine,
                    reason: "You deleted the case containing this exact event. Restore it from Event diagnostics if you want it back."
                )
            }
            if ignoredFingerprints.contains(event.fingerprint) {
                return diagnostic(
                    for: event,
                    disposition: .routine,
                    reason: "You muted this error type. Unmute it from Event diagnostics to create cases again."
                )
            }
            if isCandidate(event) {
                return diagnostic(for: event, disposition: .failure, reason: failureReason(for: event))
            }
            return diagnostic(for: event, disposition: .routine, reason: routineReason(for: event))
        }
        return SyncReport(
            sources: sources.sorted { $0.rawValue < $1.rawValue },
            diagnostics: (diagnostics + unsupported).sorted { $0.timestamp > $1.timestamp },
            sourceErrors: sourceErrors
        )
    }

    static func detect(events: [LogEvent], startingNumber: Int) -> DetectionResult {
        let uniqueEvents = deduplicated(events)
        let candidates = uniqueEvents.filter(isCandidate)
        var usedCandidateIDs = Set<UUID>()
        var detected: [SignalCase] = []
        var nextNumber = startingNumber

        for anchor in candidates.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard !usedCandidateIDs.contains(anchor.id) else { continue }

            let sameFingerprint = candidates.filter { $0.fingerprint == anchor.fingerprint }
            let related = uniqueEvents.filter { event in
                if event.fingerprint == anchor.fingerprint { return true }
                if let requestID = anchor.requestID, !requestID.isEmpty, event.requestID == requestID { return true }
                if let externalID = anchor.externalID, !externalID.isEmpty, event.externalID == externalID { return true }
                if let userID = anchor.userID, !userID.isEmpty, event.userID == userID,
                   abs(event.timestamp.timeIntervalSince(anchor.timestamp)) <= 60 { return true }
                if let route = anchor.route, !route.isEmpty, event.route == route,
                   abs(event.timestamp.timeIntervalSince(anchor.timestamp)) <= 15 { return true }
                if event.level == .deploy,
                   event.timestamp <= anchor.timestamp,
                   anchor.timestamp.timeIntervalSince(event.timestamp) <= 1_800 { return true }
                return abs(event.timestamp.timeIntervalSince(anchor.timestamp)) <= 5
                    && event.source != anchor.source
                    && (event.level == .error || anchor.level == .error)
            }

            for event in related where isCandidate(event) {
                usedCandidateIDs.insert(event.id)
            }

            let correlated = related
                .map { event in event.withCorrelation(correlation(for: event, anchor: anchor)) }
                .sorted { $0.timestamp < $1.timestamp }
            let occurrenceCount = max(1, sameFingerprint.count)
            let affectedUsers = Set(sameFingerprint.compactMap(\.userID)).count
            let firstSeen = sameFingerprint.map(\.timestamp).min() ?? anchor.timestamp
            let lastSeen = sameFingerprint.map(\.timestamp).max() ?? anchor.timestamp
            let findings = findings(for: anchor, related: correlated, occurrenceCount: occurrenceCount, affectedUsers: affectedUsers)
            let title = caseTitle(for: anchor)

            nextNumber += 1
            detected.append(
                SignalCase(
                    id: UUID(),
                    reference: "SIG-\(nextNumber)",
                    title: title,
                    summary: summary(for: anchor, related: correlated),
                    status: .new,
                    severity: severity(for: anchor, occurrences: occurrenceCount, users: affectedUsers),
                    occurrenceCount: occurrenceCount,
                    affectedUsers: affectedUsers,
                    firstSeen: firstSeen,
                    lastSeen: lastSeen,
                    release: correlated.compactMap(\.release).first ?? "Unknown release",
                    environment: anchor.metadata["environment"] ?? "Production",
                    fingerprint: anchor.fingerprint,
                    events: correlated,
                    findings: findings,
                    codeReferences: [],
                    reproduction: reproduction(for: anchor, related: correlated),
                    detectionNote: detectionNote(for: correlated)
                )
            )
        }

        return DetectionResult(
            cases: detected.sorted { $0.lastSeen > $1.lastSeen },
            candidateCount: candidates.count,
            ignoredCount: max(0, uniqueEvents.count - candidates.count)
        )
    }

    static func merge(detected: [SignalCase], into existing: [SignalCase]) -> [SignalCase] {
        var result = existing.filter { oldCase in
            detected.contains { casesShouldCoalesce(oldCase, $0) }
        }

        for incoming in detected {
            if let index = result.firstIndex(where: { $0.fingerprint == incoming.fingerprint }) {
                result[index] = combinedCase(result[index], incoming, preferring: result[index])
            } else {
                result.append(incoming)
            }
        }

        var didMerge = true
        while didMerge {
            didMerge = false
            mergeLoop: for leftIndex in result.indices {
                guard leftIndex + 1 < result.count else { continue }
                for rightIndex in (leftIndex + 1)..<result.count where casesShouldCoalesce(result[leftIndex], result[rightIndex]) {
                    let preferred = preferredCase(result[leftIndex], result[rightIndex])
                    result[leftIndex] = combinedCase(result[leftIndex], result[rightIndex], preferring: preferred)
                    result.remove(at: rightIndex)
                    didMerge = true
                    break mergeLoop
                }
            }
        }

        return result.sorted { $0.lastSeen > $1.lastSeen }
    }

    private static func casesShouldCoalesce(_ left: SignalCase, _ right: SignalCase) -> Bool {
        if left.fingerprint == right.fingerprint { return true }

        let leftFailureKeys = Set(left.events.filter(isCandidate).map(eventIdentity))
        let rightFailureKeys = Set(right.events.filter(isCandidate).map(eventIdentity))
        if !leftFailureKeys.isDisjoint(with: rightFailureKeys) { return true }

        let leftRequestIDs = Set(left.events.filter(isCandidate).compactMap { nonemptyID($0.requestID) })
        let rightRequestIDs = Set(right.events.filter(isCandidate).compactMap { nonemptyID($0.requestID) })
        return !leftRequestIDs.isDisjoint(with: rightRequestIDs)
    }

    private static func preferredCase(_ left: SignalCase, _ right: SignalCase) -> SignalCase {
        if left.occurrenceCount != right.occurrenceCount {
            return left.occurrenceCount > right.occurrenceCount ? left : right
        }
        if left.firstSeen != right.firstSeen { return left.firstSeen < right.firstSeen ? left : right }
        return referenceNumber(left.reference) <= referenceNumber(right.reference) ? left : right
    }

    private static func combinedCase(_ left: SignalCase, _ right: SignalCase, preferring preferred: SignalCase) -> SignalCase {
        let other = preferred.id == left.id ? right : left
        var combined = preferred
        let rawEvents = mergeEvents(left.events + right.events)
        let events = correlationsRecomputed(in: rawEvents, primaryFingerprint: preferred.fingerprint)
            .sorted { $0.timestamp < $1.timestamp }
        let primaryOccurrences = events.filter { isCandidate($0) && $0.fingerprint == preferred.fingerprint }.count
        let affectedUsers = Set(events.filter(isCandidate).compactMap(\.userID)).count
        let anchor = events
            .filter { isCandidate($0) && $0.fingerprint == preferred.fingerprint }
            .max(by: { $0.timestamp < $1.timestamp })
            ?? events.filter(isCandidate).max(by: { $0.timestamp < $1.timestamp })

        combined.events = events
        combined.status = statusAfterMerge(left, right)
        combined.severity = moreSevere(left.severity, right.severity)
        combined.occurrenceCount = max(max(left.occurrenceCount, right.occurrenceCount), primaryOccurrences)
        combined.affectedUsers = max(max(left.affectedUsers, right.affectedUsers), affectedUsers)
        combined.firstSeen = min(left.firstSeen, right.firstSeen)
        combined.lastSeen = max(left.lastSeen, right.lastSeen)
        combined.release = preferred.release == "Unknown release" ? other.release : preferred.release
        combined.codeReferences = Array((left.codeReferences + right.codeReferences)
            .reduce(into: [String: CodeReference]()) { $0[$1.id] = $1 }
            .values)
            .sorted { $0.path < $1.path }

        if let anchor {
            combined.summary = summary(for: anchor, related: events)
            combined.findings = findings(
                for: anchor,
                related: events,
                occurrenceCount: combined.occurrenceCount,
                affectedUsers: combined.affectedUsers
            )
            combined.reproduction = reproduction(for: anchor, related: events)
        }
        combined.detectionNote = detectionNote(for: events)
        return combined
    }

    private static func mergeEvents(_ events: [LogEvent]) -> [LogEvent] {
        var output: [LogEvent] = []
        var indices: [String: Int] = [:]
        for event in events {
            let key = eventIdentity(event)
            if let index = indices[key] {
                if correlationPriority(event.correlation) > correlationPriority(output[index].correlation) {
                    output[index] = event
                }
            } else {
                indices[key] = output.count
                output.append(event)
            }
        }
        return output
    }

    private static func correlationsRecomputed(in events: [LogEvent], primaryFingerprint: String) -> [LogEvent] {
        let requestCounts = Dictionary(grouping: events.compactMap { nonemptyID($0.requestID) }, by: { $0 })
            .mapValues(\.count)
        let externalCounts = Dictionary(grouping: events.compactMap { nonemptyID($0.externalID) }, by: { $0 })
            .mapValues(\.count)

        return events.map { event in
            if let requestID = nonemptyID(event.requestID), (requestCounts[requestID] ?? 0) > 1 {
                return event.withCorrelation(.exactID)
            }
            if let externalID = nonemptyID(event.externalID), (externalCounts[externalID] ?? 0) > 1 {
                return event.withCorrelation(.providerGroup)
            }
            if isCandidate(event), event.fingerprint == primaryFingerprint {
                return event.withCorrelation(.fingerprint)
            }
            return event
        }
    }

    private static func eventIdentity(_ event: LogEvent) -> String {
        event.externalID.map { "\(event.source.rawValue):external:\($0)" }
            ?? "\(event.source.rawValue):\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
    }

    private static func nonemptyID(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func referenceNumber(_ reference: String) -> Int {
        Int(reference.replacingOccurrences(of: "SIG-", with: "")) ?? .max
    }

    private static func correlationPriority(_ correlation: CorrelationKind) -> Int {
        switch correlation {
        case .exactID: 5
        case .providerGroup: 4
        case .fingerprint: 3
        case .standalone: 2
        case .timeWindow: 1
        }
    }

    private static func statusAfterMerge(_ left: SignalCase, _ right: SignalCase) -> CaseStatus {
        if left.status == .resolved, right.lastSeen > left.lastSeen { return .new }
        if right.status == .resolved, left.lastSeen > right.lastSeen { return .new }
        return moreAdvancedStatus(left.status, right.status)
    }

    private static func moreAdvancedStatus(_ left: CaseStatus, _ right: CaseStatus) -> CaseStatus {
        let order: [CaseStatus] = [.new, .active, .resolved]
        return (order.firstIndex(of: left) ?? 0) >= (order.firstIndex(of: right) ?? 0) ? left : right
    }

    private static func moreSevere(_ left: CaseSeverity, _ right: CaseSeverity) -> CaseSeverity {
        let order: [CaseSeverity] = [.normal, .high, .critical]
        return (order.firstIndex(of: left) ?? 0) >= (order.firstIndex(of: right) ?? 0) ? left : right
    }

    static func isCandidate(_ event: LogEvent) -> Bool {
        let text = "\(event.title) \(event.detail)".lowercased()
        let expected = [
            "card_declined", "incorrect_cvc", "insufficient_funds", "user cancelled",
            "user canceled", "invalid login credentials", "health check", "healthcheck"
        ]
        if expected.contains(where: text.contains) { return false }
        let providerSeverity = event.metadata["providerSeverity"]?.lowercased() ?? ""
        let sqlState = event.metadata["sqlState"]?.uppercased() ?? ""
        let status = Int(event.metadata["status"] ?? "") ?? 0
        let hasStructuredFailure = ["error", "fatal", "panic"].contains(where: providerSeverity.contains)
            || (sqlState.count == 5 && !["00", "01", "02", "03"].contains(String(sqlState.prefix(2))))
            || status >= 500
        if event.source == .supabase,
           !hasStructuredFailure,
           ["-- source: dashboard", "pg_temp.count_estimate", "checkpoint starting:", "checkpoint complete:"]
            .contains(where: text.contains) {
            return false
        }
        if event.level == .error { return true }
        if event.level == .warning {
            let warningPattern = #"\b(timeout|timed out|denied|failed|retry|retrying|restart|restarted|billing_issue|expired)\b"#
            return text.range(of: warningPattern, options: .regularExpression) != nil
        }
        return false
    }

    private static func diagnostic(
        for event: LogEvent,
        disposition: EventDisposition,
        reason: String
    ) -> EventDiagnostic {
        EventDiagnostic(
            timestamp: event.timestamp,
            source: event.source,
            disposition: disposition,
            title: event.title,
            detail: event.detail,
            reason: reason,
            fingerprint: event.fingerprint
        )
    }

    private static func diagnosticEventKey(_ event: LogEvent) -> String {
        event.externalID.map { "\(event.source.rawValue):external:\($0)" }
            ?? "\(event.source.rawValue):\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
    }

    private static func failureReason(for event: LogEvent) -> String {
        let severity = event.metadata["providerSeverity"]?.uppercased() ?? ""
        let sqlState = event.metadata["sqlState"]?.uppercased() ?? ""
        let status = Int(event.metadata["status"] ?? "") ?? 0
        if sqlState.count == 5 { return "The provider supplied failing SQLSTATE \(sqlState)." }
        if status >= 500 { return "The provider supplied HTTP status \(status)." }
        if ["ERROR", "FATAL", "PANIC"].contains(where: severity.contains) {
            return "The provider marked this event as \(severity)."
        }
        if event.level == .error { return "The provider classified this event as an error." }
        return "This warning contains a failure, timeout, denial, retry, restart, billing, or expiry signal."
    }

    private static func routineReason(for event: LogEvent) -> String {
        let text = "\(event.title) \(event.detail)".lowercased()
        let status = Int(event.metadata["status"] ?? "") ?? 0
        if text.contains("health check") || text.contains("healthcheck") {
            return "Health checks are expected service traffic."
        }
        if event.source == .supabase,
           ["-- source: dashboard", "pg_temp.count_estimate"].contains(where: text.contains) {
            return "This is routine Supabase Dashboard activity, not an application failure."
        }
        if event.source == .supabase,
           ["checkpoint starting:", "checkpoint complete:"].contains(where: text.contains) {
            return "This is routine Postgres maintenance activity."
        }
        if (200..<400).contains(status) { return "HTTP \(status) completed without a server failure." }
        if event.level == .deploy { return "Deploys are retained as context and do not create a case by themselves." }
        if event.level == .success { return "The provider reported a successful event." }
        if event.level == .warning { return "This warning does not contain an actionable failure pattern." }
        return "Informational activity is retained for correlation but does not create a case."
    }

    private static func correlation(for event: LogEvent, anchor: LogEvent) -> CorrelationKind {
        if let requestID = anchor.requestID, !requestID.isEmpty, event.requestID == requestID { return .exactID }
        if let externalID = anchor.externalID, !externalID.isEmpty, event.externalID == externalID { return .providerGroup }
        if event.fingerprint == anchor.fingerprint { return .fingerprint }
        if event.id == anchor.id { return .standalone }
        return .timeWindow
    }

    private static func findings(
        for anchor: LogEvent,
        related: [LogEvent],
        occurrenceCount: Int,
        affectedUsers: Int
    ) -> [CaseFinding] {
        var output: [CaseFinding] = []
        let exact = related.filter { $0.correlation.isProven }
        let exactSources = Set(exact.map(\.source))
        if exactSources.count > 1 {
            let anchorValue = anchor.requestID ?? anchor.externalID ?? "shared provider identifier"
            output.append(.init(
                title: "Exact identifier connects \(exactSources.count) sources",
                detail: "\(anchorValue) appears in \(exactSources.map(\.title).sorted().joined(separator: ", ")).",
                tone: .good
            ))
        }

        output.append(.init(
            title: anchor.title,
            detail: anchor.detail,
            tone: .failure
        ))

        let firstMatchingFailure = related
            .filter { isCandidate($0) && $0.fingerprint == anchor.fingerprint }
            .map(\.timestamp)
            .min() ?? anchor.timestamp
        if let deploy = related.last(where: { $0.level == .deploy && $0.timestamp <= firstMatchingFailure }) {
            let seconds = Int(firstMatchingFailure.timeIntervalSince(deploy.timestamp))
            let minutes = max(1, seconds / 60)
            output.append(.init(
                title: "First observed \(minutes) \(minutes == 1 ? "minute" : "minutes") after a deploy",
                detail: "This is a time correlation with \(deploy.title), not proof that the deploy caused the failure.",
                tone: .warning
            ))
        }

        if occurrenceCount > 1 {
            output.append(.init(
                title: "Repeated \(occurrenceCount) times",
                detail: affectedUsers > 0 ? "The normalized fingerprint affects \(affectedUsers) distinct users." : "The normalized error fingerprint appeared \(occurrenceCount) times.",
                tone: .neutral
            ))
        }

        return output
    }

    private static func caseTitle(for event: LogEvent) -> String {
        let title = SecretRedactor.redact(event.title).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && !["error", "log error", "request failed"].contains(title.lowercased()) {
            return title.count > 90 ? String(title.prefix(89)) + "…" : title
        }
        let detail = SecretRedactor.redact(event.detail)
        return detail.count > 90 ? String(detail.prefix(89)) + "…" : detail
    }

    private static func summary(for anchor: LogEvent, related: [LogEvent]) -> String {
        let sources = Set(related.map(\.source)).map(\.title).sorted().joined(separator: ", ")
        let link: String
        if related.contains(where: { $0.correlation.isProven }) {
            link = "Related events were connected by an exact request or provider event identifier."
        } else if related.count > 1 {
            link = "Nearby events were included as time-based context and are labeled accordingly."
        } else {
            link = "No related event from another source was found in this capture window."
        }
        return "\(anchor.source.title) recorded \(SecretRedactor.redact(anchor.detail)) Sources checked: \(sources). \(link)"
    }

    private static func severity(for event: LogEvent, occurrences: Int, users: Int) -> CaseSeverity {
        let text = "\(event.title) \(event.detail)".lowercased()
        if text.contains("webhook") || text.contains("payment") || text.contains("checkout") || users >= 10 { return .critical }
        if event.level == .error || occurrences >= 3 || users >= 3 { return .high }
        return .normal
    }

    private static func reproduction(for anchor: LogEvent, related: [LogEvent]) -> [String] {
        var steps: [String] = []
        let hasAuth = related.contains { $0.source == .supabase && $0.title.localizedCaseInsensitiveContains("auth") }
        if hasAuth { steps.append("Sign in using an account with the same role or access state as the affected request.") }
        if let route = related.compactMap(\.route).first, !route.isEmpty {
            steps.append("Perform the action that calls \(route).")
        } else {
            steps.append("Missing evidence: record the user action immediately before this event.")
        }
        steps.append("Confirm the operation produces \(anchor.title) with fingerprint \(anchor.fingerprint.suffix(24)).")
        return steps
    }

    private static func detectionNote(for events: [LogEvent]) -> String {
        let exact = events.filter { $0.correlation.isProven }.count
        let fingerprint = events.filter { $0.correlation == .fingerprint }.count
        let inferred = events.filter { $0.correlation == .timeWindow }.count
        var parts: [String] = []
        if exact > 0 { parts.append("\(exact) \(exact == 1 ? "event is" : "events are") ID-matched") }
        if fingerprint > 0 { parts.append("\(fingerprint) \(fingerprint == 1 ? "event matches" : "events match") the error fingerprint") }
        if inferred > 0 { parts.append("\(inferred) \(inferred == 1 ? "is" : "are") time-based context") }
        if parts.count > 1 { return parts.joined(separator: "; ") + "." }
        if exact > 0 {
            let sources = Set(events.filter { $0.correlation.isProven }.map(\.source))
            return sources.count > 1
                ? "All related cross-service evidence is connected by exact identifiers."
                : "\(exact) events from \(sources.first?.title ?? "one source") share an exact identifier."
        }
        if fingerprint > 0 { return parts.first.map { $0 + "." } ?? "Events share an error fingerprint." }
        if inferred > 0 { return "Related events are time-based context and do not prove causation." }
        return "This case currently contains one standalone provider signal."
    }

    private static func deduplicated(_ events: [LogEvent]) -> [LogEvent] {
        var seen = Set<String>()
        return events.filter { event in
            let key = event.externalID.map { "\(event.source.rawValue):\($0)" }
                ?? "\(event.source.rawValue):\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
            return seen.insert(key).inserted
        }
    }
}

private extension LogEvent {
    func withCorrelation(_ value: CorrelationKind) -> LogEvent {
        LogEvent(
            id: id,
            timestamp: timestamp,
            source: source,
            level: level,
            title: title,
            detail: detail,
            requestID: requestID,
            externalID: externalID,
            userID: userID,
            release: release,
            route: route,
            fingerprint: fingerprint,
            correlation: value,
            metadata: metadata
        )
    }
}


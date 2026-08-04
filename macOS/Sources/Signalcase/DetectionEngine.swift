import Foundation

struct DetectionResult {
    let cases: [SignalCase]
    let candidateCount: Int
    let ignoredCount: Int
}

enum SignalDetector {
    static func detect(events: [LogEvent], projectRoot: URL?, startingNumber: Int) -> DetectionResult {
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
            let references = RepositoryMatcher.match(events: correlated, root: projectRoot)
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
                    codeReferences: references,
                    reproduction: reproduction(for: anchor, related: correlated),
                    isDemo: false,
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
        var result = existing
        for incoming in detected {
            if let index = result.firstIndex(where: { $0.fingerprint == incoming.fingerprint && !$0.isDemo }) {
                let old = result[index]
                let combinedEvents = deduplicated(old.events + incoming.events).sorted { $0.timestamp < $1.timestamp }
                result[index].events = combinedEvents
                result[index].occurrenceCount = max(old.occurrenceCount, incoming.occurrenceCount)
                result[index].affectedUsers = max(old.affectedUsers, incoming.affectedUsers)
                result[index].firstSeen = min(old.firstSeen, incoming.firstSeen)
                result[index].lastSeen = max(old.lastSeen, incoming.lastSeen)
                result[index].findings = incoming.findings
                result[index].codeReferences = incoming.codeReferences
                result[index].reproduction = incoming.reproduction
                result[index].detectionNote = incoming.detectionNote
            } else {
                result.append(incoming)
            }
        }
        return result.sorted { $0.lastSeen > $1.lastSeen }
    }

    static func isCandidate(_ event: LogEvent) -> Bool {
        let text = "\(event.title) \(event.detail)".lowercased()
        let expected = [
            "card_declined", "incorrect_cvc", "insufficient_funds", "user cancelled",
            "user canceled", "invalid login credentials", "health check", "healthcheck"
        ]
        if expected.contains(where: text.contains) { return false }
        if event.level == .error { return true }
        if event.level == .warning {
            return ["timeout", "timed out", "denied", "failed", "retry", "restart", "billing_issue", "expired"]
                .contains(where: text.contains)
        }
        return false
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

        if let deploy = related.last(where: { $0.level == .deploy && $0.timestamp <= anchor.timestamp }) {
            let seconds = Int(anchor.timestamp.timeIntervalSince(deploy.timestamp))
            output.append(.init(
                title: "First observed \(max(1, seconds / 60)) minutes after a deploy",
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
        let inferred = events.filter { $0.correlation == .timeWindow }.count
        if exact > 0 && inferred > 0 { return "\(exact) events are ID-matched; \(inferred) are time-based context." }
        if exact > 0 {
            let sources = Set(events.filter { $0.correlation.isProven }.map(\.source))
            return sources.count > 1
                ? "All related cross-service evidence is connected by exact identifiers."
                : "\(exact) events from \(sources.first?.title ?? "one source") share an exact identifier."
        }
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

enum RepositoryMatcher {
    private static let extensions = Set(["swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "kt", "java", "sql"])

    static func match(events: [LogEvent], root: URL?) -> [CodeReference] {
        guard let root else { return directReferences(in: events, root: nil) }
        var output = directReferences(in: events, root: root)
        if output.count >= 3 { return Array(output.prefix(3)) }

        let tokens = searchTokens(events)
        guard !tokens.isEmpty,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return output }

        var inspected = 0
        while let url = enumerator.nextObject() as? URL, inspected < 1_500, output.count < 3 {
            if ["node_modules", ".build", "dist", ".next", "Pods"].contains(where: url.pathComponents.contains) {
                enumerator.skipDescendants()
                continue
            }
            guard extensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) < 600_000,
                  let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            inspected += 1

            for token in tokens where contents.localizedCaseInsensitiveContains(token) {
                let line = contents.prefix(upTo: contents.range(of: token, options: .caseInsensitive)!.lowerBound)
                    .reduce(into: 1) { count, character in if character == "\n" { count += 1 } }
                let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
                let reference = CodeReference(path: path, line: line, reason: "Contains \(token) from the captured error")
                if !output.contains(where: { $0.id == reference.id }) { output.append(reference) }
                break
            }
        }
        return Array(output.prefix(3))
    }

    private static func directReferences(in events: [LogEvent], root: URL?) -> [CodeReference] {
        let pattern = #"([A-Za-z0-9_./-]+\.(?:swift|tsx?|jsx?|py|rb|go|rs|kt|java|sql)):(\d+)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var output: [CodeReference] = []
        for event in events {
            let text = "\(event.title) \(event.detail)"
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let pathRange = Range(match.range(at: 1), in: text),
                      let lineRange = Range(match.range(at: 2), in: text),
                      let line = Int(text[lineRange]) else { continue }
                let path = String(text[pathRange])
                if let root, !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) { continue }
                let reference = CodeReference(path: path, line: line, reason: "Stack frame from \(event.source.title)")
                if !output.contains(where: { $0.id == reference.id }) { output.append(reference) }
            }
        }
        return output
    }

    private static func searchTokens(_ events: [LogEvent]) -> [String] {
        let joined = events.map { "\($0.title) \($0.detail)" }.joined(separator: " ")
        let patterns = [
            #"(?i)(?:table|column|relation|policy|function) [\"']?([a-zA-Z_][a-zA-Z0-9_]*)"#,
            #"\b(PGRST\d{3}|[0-9A-Z]{5})\b"#
        ]
        var tokens: [String] = []
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(joined.startIndex..., in: joined)
            for match in regex.matches(in: joined, range: range) {
                let group = match.numberOfRanges > 1 ? 1 : 0
                if let tokenRange = Range(match.range(at: group), in: joined) {
                    let token = String(joined[tokenRange])
                    if token.count >= 3 && !tokens.contains(token) { tokens.append(token) }
                }
            }
        }
        return Array(tokens.prefix(5))
    }
}

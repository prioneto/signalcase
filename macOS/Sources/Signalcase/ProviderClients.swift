import Foundation

struct ProviderBatch {
    var events: [LogEvent]
    var unsupported: [EventDiagnostic] = []

    static let empty = ProviderBatch(events: [])
}

struct APIJSONResponse {
    let payload: Any
    let http: HTTPURLResponse

    var linkHeader: String? { http.value(forHTTPHeaderField: "Link") }
}

enum ProviderError: LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case requestFailed(Int, String)
    case unsupportedPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .invalidResponse: "The service returned an unreadable response."
        case .requestFailed(let status, let message): "HTTP \(status): \(SecretRedactor.redact(message))"
        case .unsupportedPayload(let message): message
        }
    }
}

enum APIClient {
    private static let retryableStatusCodes = Set([408, 425, 429, 500, 502, 503, 504])
    private static let maximumAttempts = 4

    static func json(url: URL, headers: [String: String]) async throws -> Any {
        try await response(url: url, headers: headers).payload
    }

    static func response(url: URL, headers: [String: String]) async throws -> APIJSONResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Signalcase/0.2", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        var lastError: Error?
        for attempt in 0..<maximumAttempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
                if (200..<300).contains(http.statusCode) {
                    let payload: Any = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data)
                    return APIJSONResponse(payload: payload, http: http)
                }

                let error = ProviderError.requestFailed(
                    http.statusCode,
                    String(data: data.prefix(2_000), encoding: .utf8) ?? "Request failed"
                )
                guard retryableStatusCodes.contains(http.statusCode), attempt + 1 < maximumAttempts else {
                    throw error
                }
                lastError = error
                try await Task.sleep(for: .milliseconds(retryDelayMilliseconds(response: http, attempt: attempt)))
            } catch let error as URLError where isRetryable(error) && attempt + 1 < maximumAttempts {
                lastError = error
                try await Task.sleep(for: .milliseconds(retryDelayMilliseconds(response: nil, attempt: attempt)))
            } catch {
                throw error
            }
        }
        throw lastError ?? ProviderError.invalidResponse
    }

    static func retryDelayMilliseconds(response: HTTPURLResponse?, attempt: Int, now: Date = Date()) -> Int64 {
        if let value = response?.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(value) { return Int64(min(max(seconds, 0), 30) * 1_000) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            if let date = formatter.date(from: value) {
                return Int64(min(max(date.timeIntervalSince(now), 0), 30) * 1_000)
            }
        }
        if let value = response?.value(forHTTPHeaderField: "X-RateLimit-Reset"), let number = Double(value) {
            let seconds = number > now.timeIntervalSince1970 ? number - now.timeIntervalSince1970 : number
            return Int64(min(max(seconds, 0), 30) * 1_000)
        }
        let exponential = min(pow(2, Double(attempt)) * 500, 8_000)
        let jitter = Double.random(in: 0...250)
        return Int64(exponential + jitter)
    }

    private static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed, .resourceUnavailable:
            true
        default:
            false
        }
    }
}

enum SupabaseProvider {
    private static let pageSize = 500
    private static let maximumPages = 50

    static func fetchBatch(
        configuration: ProviderConfiguration,
        token: String,
        start: Date,
        end: Date
    ) async throws -> ProviderBatch {
        guard !configuration.supabaseProjectRef.isEmpty else {
            throw ProviderError.invalidConfiguration("Enter the Supabase project reference.")
        }
        guard !token.isEmpty else { throw ProviderError.invalidConfiguration("Enter a Supabase OAuth access token or personal access token.") }

        let sql = """
        select id,
               timestamp,
               event_message,
               severity_text,
               source,
               log_attributes['request.method'] as method,
               log_attributes['request.path'] as path,
               log_attributes['response.status_code'] as status_code,
               log_attributes['request.id'] as request_id,
               log_attributes['sb.auth_user'] as user_id,
               log_attributes['parsed.sql_state_code'] as sql_state,
               log_attributes['parsed.error_severity'] as error_severity
        from logs
        where source in ('edge_logs', 'postgres_logs', 'auth_logs', 'function_edge_logs', 'function_logs', 'storage_logs')
        order by timestamp desc
        limit \(pageSize)
        """
        let iso = ISO8601DateFormatter()
        var cursorEnd = end
        var allEvents: [LogEvent] = []
        var allUnsupported: [EventDiagnostic] = []
        var seen = Set<String>()

        for _ in 0..<maximumPages {
            var components = URLComponents(string: "https://api.supabase.com/v1/projects/\(configuration.supabaseProjectRef)/analytics/endpoints/logs")!
            components.queryItems = [
                .init(name: "sql", value: sql),
                .init(name: "iso_timestamp_start", value: iso.string(from: start)),
                .init(name: "iso_timestamp_end", value: iso.string(from: cursorEnd))
            ]
            let payload = try await APIClient.json(url: components.url!, headers: ["Authorization": "Bearer \(token)"])
            let rawRows = rows(from: payload)
            let pageEvents = normalize(payload)
            allUnsupported.append(contentsOf: unsupportedDiagnostics(
                payload: payload,
                normalizedCount: pageEvents.count,
                source: .supabase,
                reason: "The Supabase row did not include the standard event_message fields Signalcase understands."
            ))
            for event in pageEvents {
                let key = event.externalID ?? "\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
                if seen.insert(key).inserted { allEvents.append(event) }
            }

            guard rawRows.count >= pageSize,
                  let oldest = rawRows.compactMap({ DateParser.parse($0["timestamp"]) }).min(),
                  oldest > start else { break }
            let nextEnd = oldest.addingTimeInterval(-0.001)
            guard nextEnd < cursorEnd else { break }
            cursorEnd = nextEnd
        }

        return ProviderBatch(
            events: allEvents,
            unsupported: allUnsupported
        )
    }

    static func fetch(
        configuration: ProviderConfiguration,
        token: String,
        start: Date,
        end: Date
    ) async throws -> [LogEvent] {
        try await fetchBatch(configuration: configuration, token: token, start: start, end: end).events
    }

    static func normalize(_ payload: Any) -> [LogEvent] {
        rows(from: payload).compactMap { row in
            guard let message = nonempty(string(row, "event_message")) ?? nonempty(string(row, "message")) else { return nil }
            let sourceName = string(row, "source") ?? string(row, "source_name") ?? "supabase"
            let severity = nonempty(string(row, "error_severity"))
                ?? nonempty(string(row, "severity_text"))
                ?? nonempty(string(row, "level"))
            let structuredStatus = Int(string(row, "status_code") ?? "") ?? int(row["status_code"]) ?? 0
            let status = structuredStatus > 0 ? structuredStatus : statusCode(in: message)
            let sqlState = meaningfulSQLState(string(row, "sql_state"))
            let method = string(row, "method")
            let path = string(row, "path")
            let level = classify(severity: severity, status: status, sqlState: sqlState, message: message)
            let title: String
            if let sqlState, !sqlState.isEmpty {
                title = "Database error \(sqlState)"
            } else if let path, !path.isEmpty {
                title = "\(method ?? "REQUEST") \(path)\(status > 0 ? " · \(status)" : "")"
            } else if sourceName == "auth_logs" {
                title = message.localizedCaseInsensitiveContains("login") ? "Auth login event" : "Supabase Auth event"
            } else {
                title = message.components(separatedBy: .newlines).first.map { String($0.prefix(100)) } ?? "Supabase event"
            }
            let requestID = nonempty(string(row, "request_id")) ?? extractID(from: message, prefixes: ["req_", "request_id="])
            let userID = nonempty(string(row, "user_id")) ?? extractID(from: message, prefixes: ["usr_", "user_id="])
            let date = DateParser.parse(row["timestamp"]) ?? Date()
            let redacted = SecretRedactor.redact(message)
            return LogEvent(
                timestamp: date,
                source: .supabase,
                level: level,
                title: SecretRedactor.redact(title),
                detail: redacted,
                requestID: requestID,
                externalID: nonempty(string(row, "id")),
                userID: userID,
                route: nonempty(path),
                fingerprint: "supabase:\(sqlState ?? String(status)):\(EventFingerprint.make(source: .supabase, message: redacted))",
                metadata: SecretRedactor.redact([
                    "providerSource": sourceName,
                    "status": status > 0 ? "\(status)" : "",
                    "sqlState": sqlState ?? "",
                    "providerSeverity": severity ?? ""
                ])
            )
        }
    }

    static func reclassifyPersisted(_ event: LogEvent) -> LogEvent {
        guard event.source == .supabase else { return event }
        let status = Int(event.metadata["status"] ?? "") ?? statusCode(in: "\(event.title) \(event.detail)")
        let rawSQLState = nonempty(event.metadata["sqlState"])?.uppercased()
        let sqlState = meaningfulSQLState(rawSQLState)
        let severity = nonempty(event.metadata["providerSeverity"])
            ?? (rawSQLState?.hasPrefix("00") == true ? "info" : nil)
        let level = classify(severity: severity, status: status, sqlState: sqlState, message: "\(event.title) \(event.detail)")
        let title = event.title == "Database error 00000" ? "Postgres activity" : event.title
        var metadata = event.metadata
        metadata["status"] = status > 0 ? "\(status)" : ""
        metadata["sqlState"] = sqlState ?? ""
        return LogEvent(
            id: event.id,
            timestamp: event.timestamp,
            source: event.source,
            level: level,
            title: title,
            detail: event.detail,
            requestID: event.requestID,
            externalID: event.externalID,
            userID: event.userID,
            release: event.release,
            route: event.route,
            fingerprint: event.fingerprint,
            correlation: event.correlation,
            metadata: metadata
        )
    }

    private static func meaningfulSQLState(_ value: String?) -> String? {
        guard let value = nonempty(value)?.uppercased(), value.count == 5 else { return nil }
        let nonFailureClasses = ["00", "01", "02", "03"]
        return nonFailureClasses.contains(String(value.prefix(2))) ? nil : value
    }

    private static func classify(severity: String?, status: Int, sqlState: String?, message: String) -> EventLevel {
        let severity = severity?.lowercased() ?? ""
        if ["error", "fatal", "panic"].contains(where: severity.contains) || sqlState != nil || status >= 500 { return .error }
        if severity.contains("warn") || (400..<500).contains(status) { return .warning }
        if (200..<400).contains(status) { return .info }
        if !severity.isEmpty { return .info }

        let text = message.lowercased()
        let errorPattern = #"\b(error|fatal|panic|exception|failed|failure|denied)\b"#
        if text.range(of: errorPattern, options: .regularExpression) != nil { return .error }
        let timeoutPattern = #"\b(timeout|timed out)\b"#
        if text.range(of: timeoutPattern, options: .regularExpression) != nil { return .warning }
        return .info
    }

    private static func statusCode(in message: String) -> Int {
        let patterns = [#"\|\s*([1-5][0-9]{2})\s*\|"#, #"\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b[^\n]*?\b([1-5][0-9]{2})\b"#]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(message.startIndex..., in: message)
            if let match = regex.firstMatch(in: message, range: range),
               let valueRange = Range(match.range(at: 1), in: message),
               let value = Int(message[valueRange]) { return value }
        }
        return 0
    }
}

enum SentryProvider {
    private static let pageSize = 100
    private static let maximumPages = 50

    static func fetchBatch(
        configuration: ProviderConfiguration,
        token: String,
        start: Date,
        end: Date
    ) async throws -> ProviderBatch {
        let events = try await fetch(configuration: configuration, token: token, start: start, end: end)
        return ProviderBatch(events: events)
    }

    static func fetch(
        configuration: ProviderConfiguration,
        token: String,
        start: Date,
        end: Date
    ) async throws -> [LogEvent] {
        guard !configuration.sentryOrganization.isEmpty, !configuration.sentryProject.isEmpty else {
            throw ProviderError.invalidConfiguration("Enter the Sentry organization and project slugs.")
        }
        guard !token.isEmpty else { throw ProviderError.invalidConfiguration("Enter a Sentry token with event:read.") }
        let base = configuration.sentryBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: "\(base)/api/0/organizations/\(configuration.sentryOrganization)/issues/")!
        components.queryItems = [
            .init(name: "query", value: "lastSeen:>\(ISO8601DateFormatter().string(from: start))"),
            .init(name: "sort", value: "date"),
            .init(name: "statsPeriod", value: "24h"),
            .init(name: "project", value: configuration.sentryProject),
            .init(name: "limit", value: "\(pageSize)")
        ]
        var pageURL: URL? = components.url
        var issues: [[String: Any]] = []

        for _ in 0..<maximumPages {
            guard let currentURL = pageURL else { break }
            let response = try await APIClient.response(url: currentURL, headers: ["Authorization": "Bearer \(token)"])
            issues.append(contentsOf: rows(from: response.payload))
            pageURL = nextPageURL(linkHeader: response.linkHeader)
        }

        var events: [LogEvent] = []

        for issue in issues {
            guard let issueID = string(issue, "id") else { continue }
            let latestURL = URL(string: "\(base)/api/0/organizations/\(configuration.sentryOrganization)/issues/\(issueID)/events/latest/")!
            if let latest = try? await APIClient.json(url: latestURL, headers: ["Authorization": "Bearer \(token)"]),
               let dictionary = latest as? [String: Any],
               let normalized = normalizeEvent(dictionary, issue: issue) {
                events.append(normalized)
            } else if let normalized = normalizeIssue(issue) {
                events.append(normalized)
            }
        }
        return events.filter { $0.timestamp >= start && $0.timestamp <= end.addingTimeInterval(60) }
    }

    static func nextPageURL(linkHeader: String?) -> URL? {
        guard let linkHeader else { return nil }
        for component in linkHeader.split(separator: ",") {
            let value = String(component)
            guard value.contains(#"rel="next""#), value.contains(#"results="true""#),
                  let start = value.firstIndex(of: "<"), let end = value[start...].firstIndex(of: ">") else { continue }
            return URL(string: String(value[value.index(after: start)..<end]))
        }
        return nil
    }

    static func normalizeIssue(_ issue: [String: Any]) -> LogEvent? {
        guard let title = string(issue, "title") else { return nil }
        let metadata = issue["metadata"] as? [String: Any]
        let count = string(issue, "count") ?? "1"
        let users = int(issue["userCount"]) ?? 0
        return LogEvent(
            timestamp: DateParser.parse(issue["lastSeen"]) ?? Date(),
            source: .sentry,
            level: sentryLevel(string(issue, "level")),
            title: SecretRedactor.redact(title),
            detail: SecretRedactor.redact(string(metadata ?? [:], "value") ?? string(issue, "culprit") ?? "Sentry issue · \(count) events"),
            externalID: string(issue, "id"),
            fingerprint: "sentry:\(string(issue, "id") ?? EventFingerprint.make(source: .sentry, message: title))",
            metadata: ["issueCount": count, "affectedUsers": "\(users)", "permalink": string(issue, "permalink") ?? ""]
        )
    }

    static func normalizeEvent(_ event: [String: Any], issue: [String: Any]) -> LogEvent? {
        let title = string(event, "title") ?? string(issue, "title") ?? "Sentry error"
        let tags = dictionaryFromPairs(event["tags"])
        var detail = string(event, "message") ?? string(issue, "culprit") ?? "Sentry captured an exception."
        var route = tags["transaction"]
        var framePath: String?

        if let entries = event["entries"] as? [[String: Any]],
           let exception = entries.first(where: { string($0, "type") == "exception" }),
           let data = exception["data"] as? [String: Any],
           let values = data["values"] as? [[String: Any]],
           let value = values.last {
            let type = string(value, "type") ?? "Exception"
            let valueMessage = string(value, "value") ?? detail
            detail = "\(type): \(valueMessage)"
            if let stacktrace = value["stacktrace"] as? [String: Any],
               let frames = stacktrace["frames"] as? [[String: Any]],
               let frame = frames.last(where: { bool($0["inApp"]) == true }) ?? frames.last {
                let filename = string(frame, "filename") ?? string(frame, "absPath")
                let line = int(frame["lineNo"])
                if let filename { framePath = line.map { "\(filename):\($0)" } ?? filename }
                route = route ?? string(frame, "function")
            }
        }

        if let framePath { detail += " · \(framePath)" }
        let requestID = tags["request_id"] ?? tags["request-id"] ?? tags["trace_id"]
        let user = event["user"] as? [String: Any]
        let issueID = string(issue, "id") ?? string(event, "groupID")
        return LogEvent(
            timestamp: DateParser.parse(event["dateCreated"]) ?? DateParser.parse(issue["lastSeen"]) ?? Date(),
            source: .sentry,
            level: sentryLevel(string(event, "level") ?? string(issue, "level")),
            title: SecretRedactor.redact(title),
            detail: SecretRedactor.redact(detail),
            requestID: nonempty(requestID),
            externalID: string(event, "eventID") ?? string(event, "id"),
            userID: string(user ?? [:], "id"),
            release: tags["release"],
            route: nonempty(route),
            fingerprint: "sentry:\(issueID ?? EventFingerprint.make(source: .sentry, message: title))",
            metadata: SecretRedactor.redact([
                "issueID": issueID ?? "",
                "issueCount": string(issue, "count") ?? "1",
                "affectedUsers": "\(int(issue["userCount"]) ?? 0)",
                "permalink": string(issue, "permalink") ?? ""
            ])
        )
    }

    private static func sentryLevel(_ value: String?) -> EventLevel {
        switch value?.lowercased() {
        case "fatal", "error": .error
        case "warning": .warning
        default: .info
        }
    }
}

enum StripeProvider {
    private static let pageSize = 100
    private static let maximumPages = 50

    static func fetchBatch(token: String, start: Date, end: Date) async throws -> ProviderBatch {
        guard !token.isEmpty else { throw ProviderError.invalidConfiguration("Enter a restricted Stripe key with read access to Events.") }
        async let allPayload = requestAll(token: token, start: start, end: end, failuresOnly: false)
        async let failedPayload = requestAll(token: token, start: start, end: end, failuresOnly: true)
        let (all, failed) = try await (allPayload, failedPayload)
        let failedIDs = Set(rows(from: failed).compactMap { string($0, "id") })
        let events = normalize(all, failedDeliveryIDs: failedIDs)
        return ProviderBatch(
            events: events,
            unsupported: unsupportedDiagnostics(
                payload: all,
                normalizedCount: events.count,
                source: .stripe,
                reason: "The Stripe event was missing its event type or event ID."
            )
        )
    }

    static func fetch(token: String, start: Date, end: Date) async throws -> [LogEvent] {
        try await fetchBatch(token: token, start: start, end: end).events
    }

    private static func requestAll(token: String, start: Date, end: Date, failuresOnly: Bool) async throws -> Any {
        var collected: [[String: Any]] = []
        var cursor: String?

        for _ in 0..<maximumPages {
            var components = URLComponents(string: "https://api.stripe.com/v1/events")!
            var items: [URLQueryItem] = [
                .init(name: "created[gte]", value: "\(Int(start.timeIntervalSince1970))"),
                .init(name: "created[lte]", value: "\(Int(end.timeIntervalSince1970))"),
                .init(name: "limit", value: "\(pageSize)")
            ]
            if failuresOnly { items.append(.init(name: "delivery_success", value: "false")) }
            if let cursor { items.append(.init(name: "starting_after", value: cursor)) }
            components.queryItems = items

            let payload = try await APIClient.json(url: components.url!, headers: ["Authorization": "Bearer \(token)"])
            let page = rows(from: payload)
            collected.append(contentsOf: page)
            guard nextCursor(payload: payload) != nil,
                  let next = page.last.flatMap({ string($0, "id") }),
                  next != cursor else { break }
            cursor = next
        }
        return ["data": collected]
    }

    static func nextCursor(payload: Any) -> String? {
        guard let dictionary = payload as? [String: Any], bool(dictionary["has_more"]) == true else { return nil }
        return rows(from: payload).last.flatMap { string($0, "id") }
    }

    static func normalize(_ payload: Any, failedDeliveryIDs: Set<String> = []) -> [LogEvent] {
        rows(from: payload).compactMap { event in
            guard let type = string(event, "type"), let id = string(event, "id") else { return nil }
            let data = event["data"] as? [String: Any]
            let object = data?["object"] as? [String: Any] ?? [:]
            let metadata = object["metadata"] as? [String: Any] ?? [:]
            let objectID = string(object, "id")
            let customer = string(object, "customer")
            let status = string(object, "status")
            let request = event["request"] as? [String: Any]
            let requestID = string(request ?? [:], "id") ?? string(metadata, "request_id")
            let isFailure = failedDeliveryIDs.contains(id)
                || ["failed", "dispute", "billing_issue", "requires_payment_method"].contains(where: type.lowercased().contains)
            let isSuccess = ["succeeded", ".paid", "completed"].contains(where: type.lowercased().contains)
            let level: EventLevel = isFailure ? .error : (isSuccess ? .success : .info)
            var detail = [objectID, customer, status].compactMap { $0 }.joined(separator: " · ")
            if failedDeliveryIDs.contains(id) { detail += detail.isEmpty ? "Webhook delivery failed or remains pending" : " · webhook delivery failed or remains pending" }
            return LogEvent(
                timestamp: DateParser.parse(event["created"]) ?? Date(),
                source: .stripe,
                level: level,
                title: type,
                detail: SecretRedactor.redact(detail.isEmpty ? "Stripe event \(id)" : detail),
                requestID: nonempty(requestID),
                externalID: id,
                userID: string(metadata, "user_id") ?? customer,
                route: "Stripe event",
                fingerprint: "stripe:\(type):\(status ?? (isFailure ? "delivery_failed" : "event"))",
                metadata: SecretRedactor.redact([
                    "livemode": bool(event["livemode"]) == true ? "true" : "false",
                    "objectID": objectID ?? "",
                    "customer": customer ?? "",
                    "deliveryFailed": failedDeliveryIDs.contains(id) ? "true" : "false"
                ])
            )
        }
    }
}

enum RenderProvider {
    struct LogPageCursor: Equatable {
        let startTime: String
        let endTime: String
    }

    private static let pageSize = 100
    private static let maximumPages = 50

    static func fetchBatch(
        configuration: ProviderConfiguration,
        token: String,
        start: Date,
        end: Date
    ) async throws -> ProviderBatch {
        let resources = configuration.renderResourceIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !configuration.renderOwnerID.isEmpty, !resources.isEmpty else {
            throw ProviderError.invalidConfiguration("Enter the Render workspace owner ID and at least one service ID.")
        }
        guard !token.isEmpty else { throw ProviderError.invalidConfiguration("Enter a Render API key.") }

        let iso = ISO8601DateFormatter()
        var logEvents: [LogEvent] = []
        var deployEvents: [LogEvent] = []
        var unsupported: [EventDiagnostic] = []

        var logStart = iso.string(from: start)
        var logEnd = iso.string(from: end)
        var previousLogCursor: LogPageCursor?
        for _ in 0..<maximumPages {
            var logComponents = URLComponents(string: "https://api.render.com/v1/logs")!
            var items: [URLQueryItem] = [
                .init(name: "ownerId", value: configuration.renderOwnerID),
                .init(name: "startTime", value: logStart),
                .init(name: "endTime", value: logEnd),
                .init(name: "direction", value: "forward"),
                .init(name: "limit", value: "\(pageSize)")
            ]
            items.append(contentsOf: resources.map { .init(name: "resource", value: $0) })
            logComponents.queryItems = items
            let payload = try await APIClient.json(url: logComponents.url!, headers: ["Authorization": "Bearer \(token)"])
            let normalized = normalizeLogs(payload)
            logEvents.append(contentsOf: normalized)
            unsupported.append(contentsOf: unsupportedDiagnostics(
                payload: payload,
                normalizedCount: normalized.count,
                source: .render,
                reason: "The Render log record did not contain a message field."
            ))
            guard let cursor = logPageCursor(payload: payload), cursor != previousLogCursor else { break }
            previousLogCursor = cursor
            logStart = cursor.startTime
            logEnd = cursor.endTime
        }

        for resource in resources {
            var cursor: String?
            do {
                for _ in 0..<maximumPages {
                    var deployComponents = URLComponents(string: "https://api.render.com/v1/services/\(resource)/deploys")!
                    var queryItems: [URLQueryItem] = [
                        .init(name: "createdAfter", value: iso.string(from: start.addingTimeInterval(-1_800))),
                        .init(name: "limit", value: "\(pageSize)")
                    ]
                    if let cursor { queryItems.append(.init(name: "cursor", value: cursor)) }
                    deployComponents.queryItems = queryItems
                    let payload = try await APIClient.json(url: deployComponents.url!, headers: ["Authorization": "Bearer \(token)"])
                    let normalized = normalizeDeploys(payload, resourceID: resource)
                    deployEvents.append(contentsOf: normalized)
                    unsupported.append(contentsOf: unsupportedDiagnostics(
                        payload: payload,
                        normalizedCount: normalized.count,
                        source: .render,
                        reason: "The Render deploy record was missing its deploy ID."
                    ))
                    guard let next = deployPageCursor(payload: payload), next != cursor else { break }
                    cursor = next
                }
            } catch {
                unsupported.append(EventDiagnostic(
                    source: .render,
                    disposition: .unsupported,
                    title: "Deploy history unavailable",
                    detail: resource,
                    reason: SecretRedactor.redact(error.localizedDescription)
                ))
            }
        }
        return ProviderBatch(events: deduplicate(logEvents + deployEvents), unsupported: unsupported)
    }

    static func fetch(
        configuration: ProviderConfiguration,
        token: String,
        start: Date,
        end: Date
    ) async throws -> [LogEvent] {
        try await fetchBatch(configuration: configuration, token: token, start: start, end: end).events
    }

    static func normalizeLogs(_ payload: Any) -> [LogEvent] {
        rows(from: payload).compactMap { row in
            let labels = labelsDictionary(row["labels"])
            guard let message = nonempty(string(row, "message")) ?? nonempty(string(row, "text")) ?? nonempty(string(row, "log")) else { return nil }
            let levelString = (string(row, "level") ?? labels["level"] ?? "info").lowercased()
            let level: EventLevel = levelString.contains("error") || levelString.contains("fatal")
                ? .error
                : (levelString.contains("warn") ? .warning : .info)
            let requestID = labels["request_id"] ?? labels["requestId"] ?? extractID(from: message, prefixes: ["req_", "request_id="])
            let resource = string(row, "resource") ?? labels["resource"] ?? labels["service"]
            let route = labels["path"] ?? labels["route"]
            return LogEvent(
                timestamp: DateParser.parse(row["timestamp"]) ?? DateParser.parse(row["time"]) ?? Date(),
                source: .render,
                level: level,
                title: level == .error ? "Render service error" : "Render service log",
                detail: SecretRedactor.redact(message),
                requestID: nonempty(requestID),
                externalID: string(row, "id"),
                userID: labels["user_id"],
                release: labels["release"] ?? labels["commit"],
                route: route,
                fingerprint: "render:\(resource ?? "service"):\(EventFingerprint.make(source: .render, message: message))",
                metadata: SecretRedactor.redact(labels.merging(["resource": resource ?? ""]) { current, _ in current })
            )
        }
    }

    static func normalizeDeploys(_ payload: Any, resourceID: String) -> [LogEvent] {
        rows(from: payload).compactMap { wrapper in
            let deploy = wrapper["deploy"] as? [String: Any] ?? wrapper
            guard let id = string(deploy, "id") else { return nil }
            let commit = deploy["commit"] as? [String: Any]
            let commitID = string(commit ?? [:], "id") ?? string(deploy, "commitId")
            let status = string(deploy, "status") ?? "deploy"
            let level: EventLevel = status.localizedCaseInsensitiveContains("fail") ? .error : .deploy
            return LogEvent(
                timestamp: DateParser.parse(deploy["finishedAt"]) ?? DateParser.parse(deploy["createdAt"]) ?? Date(),
                source: .render,
                level: level,
                title: level == .error ? "Render deploy failed" : "Render deploy \(status)",
                detail: "\(resourceID)\(commitID.map { " · \($0)" } ?? "")",
                externalID: id,
                release: commitID,
                fingerprint: "render:deploy:\(id)",
                metadata: ["resource": resourceID, "status": status]
            )
        }
    }

    static func logPageCursor(payload: Any) -> LogPageCursor? {
        guard let dictionary = payload as? [String: Any], bool(dictionary["hasMore"]) == true,
              let start = string(dictionary, "nextStartTime"), let end = string(dictionary, "nextEndTime") else { return nil }
        return LogPageCursor(startTime: start, endTime: end)
    }

    static func deployPageCursor(payload: Any) -> String? {
        let page = rows(from: payload)
        guard page.count >= pageSize else { return nil }
        return page.last.flatMap { string($0, "cursor") }
    }

    private static func deduplicate(_ events: [LogEvent]) -> [LogEvent] {
        var seen = Set<String>()
        return events.filter { event in
            let key = event.externalID ?? "\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
            return seen.insert(key).inserted
        }
    }
}

enum RevenueCatProvider {
    static func normalizeWebhook(_ payload: Any) throws -> LogEvent {
        guard let root = payload as? [String: Any],
              let event = root["event"] as? [String: Any],
              let type = string(event, "type"),
              let id = string(event, "id") else {
            throw ProviderError.unsupportedPayload("This is not a RevenueCat webhook payload.")
        }
        let userID = string(event, "app_user_id") ?? string(event, "original_app_user_id")
        let product = string(event, "product_id")
        let store = string(event, "store")
        let environment = string(event, "environment") ?? "PRODUCTION"
        let errorTypes = ["BILLING_ISSUE", "EXPIRATION", "CANCELLATION", "TRANSFER"]
        let level: EventLevel = errorTypes.contains(type.uppercased()) ? .warning : .success
        let detail = [product, store, userID].compactMap { $0 }.joined(separator: " · ")
        return LogEvent(
            timestamp: DateParser.parse(event["event_timestamp_ms"]) ?? Date(),
            source: .revenueCat,
            level: level,
            title: type.uppercased(),
            detail: SecretRedactor.redact(detail.isEmpty ? "RevenueCat event" : detail),
            externalID: id,
            userID: userID,
            route: "RevenueCat webhook",
            fingerprint: "revenuecat:\(type.lowercased()):\(product ?? "event")",
            metadata: SecretRedactor.redact([
                "product": product ?? "",
                "store": store ?? "",
                "environment": environment,
                "transactionID": string(event, "transaction_id") ?? ""
            ])
        )
    }
}

enum ApplicationEventProvider {
    static func normalize(_ payload: Any) throws -> LogEvent {
        guard let event = payload as? [String: Any] else {
            throw ProviderError.unsupportedPayload("Application events must be JSON objects.")
        }
        guard let message = nonempty(string(event, "message"))
            ?? nonempty(string(event, "detail"))
            ?? nonempty(string(event, "title")) else {
            throw ProviderError.unsupportedPayload("Application events need a message, detail, or title field.")
        }
        let title = string(event, "title") ?? message.components(separatedBy: .newlines).first ?? "Application event"
        let levelText = (string(event, "level") ?? "info").lowercased()
        let level: EventLevel = levelText.contains("error") || levelText.contains("fatal")
            ? .error
            : (levelText.contains("warn") ? .warning : .info)
        return LogEvent(
            timestamp: DateParser.parse(event["timestamp"]) ?? Date(),
            source: .application,
            level: level,
            title: SecretRedactor.redact(title),
            detail: SecretRedactor.redact(message),
            requestID: string(event, "request_id") ?? string(event, "requestId") ?? string(event, "trace_id"),
            externalID: string(event, "event_id") ?? string(event, "id"),
            userID: string(event, "user_id") ?? string(event, "userId"),
            release: string(event, "release") ?? string(event, "commit"),
            route: string(event, "route") ?? string(event, "path") ?? string(event, "operation"),
            fingerprint: string(event, "fingerprint"),
            metadata: SecretRedactor.redact(stringDictionary(event["metadata"]))
        )
    }
}

// MARK: - Flexible JSON helpers

func rows(from payload: Any) -> [[String: Any]] {
    if let rows = payload as? [[String: Any]] { return rows }
    guard let dictionary = payload as? [String: Any] else { return [] }
    for key in ["data", "result", "logs", "events", "items"] {
        if let rows = dictionary[key] as? [[String: Any]] { return rows }
    }
    return []
}

private func unsupportedDiagnostics(
    payload: Any,
    normalizedCount: Int,
    source: LogSource,
    reason: String
) -> [EventDiagnostic] {
    let rawRows = rows(from: payload)
    let count = max(0, rawRows.count - normalizedCount)
    guard count > 0 else { return [] }
    return (0..<count).map { index in
        EventDiagnostic(
            source: source,
            disposition: .unsupported,
            title: "Unsupported \(source.title) record",
            detail: "Record \(index + 1) of \(count) could not be normalized.",
            reason: reason
        )
    }
}

func string(_ dictionary: [String: Any], _ key: String) -> String? {
    guard let value = dictionary[key], !(value is NSNull) else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

func int(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) }
    return nil
}

func bool(_ value: Any?) -> Bool? {
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    if let string = value as? String { return ["true", "1", "yes"].contains(string.lowercased()) }
    return nil
}

func nonempty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return value
}

func stringDictionary(_ value: Any?) -> [String: String] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
        if let string = value as? String { return (key, string) }
        if let number = value as? NSNumber { return (key, number.stringValue) }
        return nil
    })
}

func dictionaryFromPairs(_ value: Any?) -> [String: String] {
    guard let pairs = value as? [[String: Any]] else { return stringDictionary(value) }
    return Dictionary(uniqueKeysWithValues: pairs.compactMap { pair in
        guard let key = string(pair, "key"), let value = string(pair, "value") else { return nil }
        return (key, value)
    })
}

func labelsDictionary(_ value: Any?) -> [String: String] {
    if let dictionary = value as? [String: Any] { return stringDictionary(dictionary) }
    guard let labels = value as? [[String: Any]] else { return [:] }
    return Dictionary(uniqueKeysWithValues: labels.compactMap { label in
        let key = string(label, "name") ?? string(label, "key")
        let value = string(label, "value")
        guard let key, let value else { return nil }
        return (key, value)
    })
}

func extractID(from value: String, prefixes: [String]) -> String? {
    for prefix in prefixes {
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "(?i)\\b(\(escaped)[A-Za-z0-9_-]+)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(value.startIndex..., in: value)
        if let match = regex.firstMatch(in: value, range: range),
           let matchRange = Range(match.range(at: 1), in: value) {
            return String(value[matchRange])
        }
    }
    return nil
}

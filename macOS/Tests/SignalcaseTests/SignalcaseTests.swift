import XCTest
import CryptoKit
@testable import Signalcase

final class SignalcaseTests: XCTestCase {
    func testFingerprintRemovesChangingIdentifiersAndNumbers() {
        let first = EventFingerprint.make(
            source: .supabase,
            message: "User 41 failed request 2b4d2b90-2d1b-4e36-b993-53f61c900001 after 500 ms"
        )
        let second = EventFingerprint.make(
            source: .supabase,
            message: "User 99 failed request 5c7f1e11-1a2c-4d08-8210-9c0a1af00002 after 800 ms"
        )

        XCTAssertEqual(first, second)
    }

    func testWorkflowActionsHaveUsefulDestinations() {
        XCTAssertEqual(CaseStatus.new.actionDestination, .active)
        XCTAssertEqual(CaseStatus.active.actionDestination, .resolved)
        XCTAssertEqual(CaseStatus.resolved.actionDestination, .active)
    }

    func testLegacyWorkflowStatusesDecodeIntoTheSimplerLifecycle() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(CaseStatus.self, from: Data("\"triaged\"".utf8)), .active)
        XCTAssertEqual(try decoder.decode(CaseStatus.self, from: Data("\"fixing\"".utf8)), .active)
        XCTAssertEqual(try decoder.decode(CaseStatus.self, from: Data("\"verified\"".utf8)), .resolved)
    }

    func testResolvedCaseReopensOnlyForANewerOccurrence() {
        let now = Date()
        let first = LogEvent(
            timestamp: now,
            source: .application,
            level: .error,
            title: "Profile failed to load",
            detail: "request failed",
            fingerprint: "app:profile-load"
        )
        let initialDetection = SignalDetector.detect(events: [first], startingNumber: 0)
        var resolved = initialDetection.cases[0]
        resolved.status = .resolved

        let duplicateSync = SignalDetector.merge(detected: initialDetection.cases, into: [resolved])
        XCTAssertEqual(duplicateSync.first?.status, .resolved)

        let recurrence = LogEvent(
            timestamp: now.addingTimeInterval(60),
            source: .application,
            level: .error,
            title: "Profile failed to load",
            detail: "request failed again",
            fingerprint: "app:profile-load"
        )
        let recurrenceDetection = SignalDetector.detect(
            events: [first, recurrence],
            startingNumber: 1
        )
        let reopened = SignalDetector.merge(detected: recurrenceDetection.cases, into: [resolved])

        XCTAssertEqual(reopened.count, 1)
        XCTAssertEqual(reopened.first?.status, .new)
        XCTAssertEqual(reopened.first?.id, resolved.id)
        XCTAssertEqual(reopened.first?.occurrenceCount, 2)
    }

    @MainActor
    func testRevenueCatIsDisconnectedUntilAnEventArrives() {
        XCTAssertEqual(
            AppModel.connectionState(.revenueCat, configuration: .empty, events: []),
            .disconnected
        )

        let webhook = LogEvent(
            timestamp: Date(),
            source: .revenueCat,
            level: .success,
            title: "INITIAL_PURCHASE",
            detail: "pro_monthly",
            externalID: "rc_evt_1"
        )
        XCTAssertEqual(
            AppModel.connectionState(.revenueCat, configuration: .empty, events: [webhook]),
            .connected
        )
    }

    func testSecretRedactionBeforePersistence() {
        let value = "Authorization: Bearer abc.def.ghi token=supersecret person@example.com 4242 4242 4242 4242"
        let redacted = SecretRedactor.redact(value)

        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertFalse(redacted.contains("person@example.com"))
        XCTAssertFalse(redacted.contains("4242 4242"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testSupabaseUnifiedLogNormalization() {
        let events = SupabaseProvider.normalize([[
            "id": "sb-log-1",
            "timestamp": "2026-08-05T00:25:42Z",
            "source": "postgres_logs",
            "event_message": "permission denied for table profiles",
            "severity_text": "ERROR",
            "request_id": "req_shared_17",
            "sql_state": "42501"
        ]])

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].source, .supabase)
        XCTAssertEqual(events[0].level, .error)
        XCTAssertEqual(events[0].requestID, "req_shared_17")
        XCTAssertTrue(events[0].title.contains("42501"))
    }

    func testSupabaseSuccessfulRowsNeverBecomeCases() {
        let payload: [[String: Any]] = [
            [
                "id": "edge-success",
                "timestamp": "2026-08-05T00:25:42Z",
                "source": "edge_logs",
                "event_message": "GET | 200 | https://project.supabase.co/auth/v1/health",
                "severity_text": "INFO",
                "status_code": "200",
                "sql_state": ""
            ],
            [
                "id": "postgres-success",
                "timestamp": "2026-08-05T00:25:43Z",
                "source": "postgres_logs",
                "event_message": "checkpoint complete: wrote 14 buffers",
                "severity_text": "INFO",
                "error_severity": "LOG",
                "sql_state": "00000"
            ],
            [
                "id": "storage-success",
                "timestamp": "2026-08-05T00:25:44Z",
                "source": "storage_logs",
                "event_message": "project | GET | 200 | 10.0.0.1 | req-pid | /tenants/project",
                "severity_text": "INFO",
                "sql_state": ""
            ]
        ]

        let events = SupabaseProvider.normalize(payload)
        XCTAssertEqual(events.map(\.level), [.info, .info, .info])
        XCTAssertEqual(SignalDetector.detect(events: events, startingNumber: 0).cases.count, 0)
    }

    func testSupabaseUnstructured500IsAnError() {
        let events = SupabaseProvider.normalize([[
            "id": "storage-failure",
            "timestamp": "2026-08-05T00:25:42Z",
            "source": "storage_logs",
            "event_message": "project | POST | 500 | 10.0.0.1 | req-pid | /object/upload",
            "severity_text": "INFO",
            "sql_state": ""
        ]])

        XCTAssertEqual(events.first?.level, .error)
        XCTAssertEqual(SignalDetector.detect(events: events, startingNumber: 0).cases.count, 1)
    }

    func testPreviouslySavedSupabaseSuccessIsReclassified() {
        let old = LogEvent(
            timestamp: Date(),
            source: .supabase,
            level: .error,
            title: "Database error 00000",
            detail: "checkpoint starting: time",
            metadata: ["providerSource": "postgres_logs", "sqlState": "00000", "status": ""]
        )

        let migrated = SupabaseProvider.reclassifyPersisted(old)
        XCTAssertEqual(migrated.level, .info)
        XCTAssertEqual(migrated.title, "Postgres activity")
        XCTAssertFalse(SignalDetector.isCandidate(migrated))
    }

    func testSupabaseDashboardCountEstimateNeverBecomesACase() {
        let dashboardQuery = """
        statement: SET statement_timeout='58s'; SET idle_session_timeout='58s';

        CREATE OR REPLACE FUNCTION pg_temp.count_estimate(
            query text
        ) RETURNS integer LANGUAGE plpgsql AS $$
        DECLARE
            plan jsonb;
        BEGIN
            EXECUTE 'EXPLAIN (FORMAT JSON)' || query INTO plan;
            RETURN plan->0->'Plan'->'Plan Rows';
        END;
        $$;

        select count(*) from public.athletes;
        -- source: dashboard
        """
        let events = SupabaseProvider.normalize([[
            "id": "dashboard-count",
            "timestamp": "2026-08-04T22:53:18.744Z",
            "source": "postgres_logs",
            "event_message": dashboardQuery,
            "severity_text": "INFO",
            "error_severity": "LOG",
            "sql_state": "00000"
        ]])

        XCTAssertEqual(events.first?.level, .info)
        XCTAssertFalse(events.first.map(SignalDetector.isCandidate) ?? true)
        XCTAssertEqual(SignalDetector.detect(events: events, startingNumber: 0).cases.count, 0)
    }

    func testStructuredSupabaseDashboardErrorIsStillACase() {
        let events = SupabaseProvider.normalize([[
            "id": "dashboard-error",
            "timestamp": "2026-08-04T22:53:18.744Z",
            "source": "postgres_logs",
            "event_message": "permission denied for table athletes -- source: dashboard",
            "severity_text": "ERROR",
            "error_severity": "ERROR",
            "sql_state": "42501"
        ]])

        XCTAssertEqual(events.first?.level, .error)
        XCTAssertTrue(events.first.map(SignalDetector.isCandidate) ?? false)
        XCTAssertEqual(SignalDetector.detect(events: events, startingNumber: 0).cases.count, 1)
    }

    func testPersistedDashboardQueryAndGenericBeginDoNotCreateEvidence() throws {
        let dashboardQuery = """
        statement: SET statement_timeout='58s';
        CREATE OR REPLACE FUNCTION pg_temp.count_estimate(query text) RETURNS integer AS $$
        BEGIN
          RETURN 1;
        END;
        $$ LANGUAGE plpgsql;
        -- source: dashboard
        """
        let old = LogEvent(
            timestamp: Date(),
            source: .supabase,
            level: .warning,
            title: "Postgres activity",
            detail: dashboardQuery,
            externalID: "old-dashboard-count",
            fingerprint: "supabase:00000:dashboard-count",
            metadata: ["providerSource": "postgres_logs", "sqlState": "", "status": ""]
        )

        let migrated = SupabaseProvider.reclassifyPersisted(old)
        XCTAssertEqual(migrated.level, .info)
        XCTAssertFalse(SignalDetector.isCandidate(migrated))
    }

    func testMergeDropsCasesNoLongerBackedByDetectedFailures() {
        let stale = SignalDetector.detect(
            events: [LogEvent(
                timestamp: Date(),
                source: .application,
                level: .error,
                title: "Test failure",
                detail: "A real detected failure"
            )],
            startingNumber: 0
        ).cases[0]
        XCTAssertTrue(SignalDetector.merge(detected: [], into: [stale]).isEmpty)
    }

    func testStripeFailedDeliveryNormalization() {
        let payload: [String: Any] = ["data": [[
            "id": "evt_123",
            "type": "checkout.session.completed",
            "created": 1_786_000_000,
            "livemode": false,
            "request": ["id": "req_shared_17"],
            "data": ["object": ["id": "cs_123", "customer": "cus_123", "status": "complete"]]
        ]]]
        let event = StripeProvider.normalize(payload, failedDeliveryIDs: ["evt_123"]).first

        XCTAssertEqual(event?.level, .error)
        XCTAssertEqual(event?.externalID, "evt_123")
        XCTAssertEqual(event?.requestID, "req_shared_17")
        XCTAssertEqual(event?.metadata["deliveryFailed"], "true")
    }

    func testRevenueCatWebhookNormalization() throws {
        let event = try RevenueCatProvider.normalizeWebhook([
            "event": [
                "id": "rc_evt_1",
                "type": "BILLING_ISSUE",
                "event_timestamp_ms": 1_786_000_000_000,
                "app_user_id": "usr_42",
                "product_id": "pro_monthly",
                "environment": "PRODUCTION"
            ]
        ])

        XCTAssertEqual(event.source, .revenueCat)
        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.externalID, "rc_evt_1")
        XCTAssertEqual(event.userID, "usr_42")
    }

    func testRevenueCatSignatureRequiresFreshConstantTimeMatch() throws {
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let body = Data(#"{"event":{"id":"rc_evt_1"}}"#.utf8)
        let secret = "whsec_test"
        let timestamp = String(Int(now.timeIntervalSince1970))
        var signed = Data("\(timestamp).".utf8)
        signed.append(body)
        let signature = Data(HMAC<SHA256>.authenticationCode(
            for: signed,
            using: SymmetricKey(data: Data(secret.utf8))
        )).map { String(format: "%02x", $0) }.joined()

        XCTAssertNoThrow(try WebhookSecurity.verifyRevenueCatSignature(
            header: "t=\(timestamp),v1=\(signature)",
            body: body,
            secret: secret,
            now: now
        ))
        XCTAssertThrowsError(try WebhookSecurity.verifyRevenueCatSignature(
            header: "t=\(timestamp),v1=\(String(repeating: "0", count: 64))",
            body: body,
            secret: secret,
            now: now
        ))
        XCTAssertThrowsError(try WebhookSecurity.verifyRevenueCatSignature(
            header: "t=\(timestamp),v1=\(signature),v1=\(signature)",
            body: body,
            secret: secret,
            now: now
        ))
        XCTAssertThrowsError(try WebhookSecurity.verifyRevenueCatSignature(
            header: "t=\(timestamp),v1=\(signature)",
            body: body,
            secret: secret,
            now: now.addingTimeInterval(301)
        ))
    }

    func testReceiverAuthorizationIsMandatory() {
        XCTAssertThrowsError(try WebhookSecurity.verifyAuthorization(received: nil, expected: nil))
        XCTAssertThrowsError(try WebhookSecurity.verifyAuthorization(received: "Bearer wrong", expected: "Bearer right"))
        XCTAssertNoThrow(try WebhookSecurity.verifyAuthorization(received: "Bearer right", expected: "Bearer right"))
    }

    func testProviderPaginationContracts() throws {
        let stripe: [String: Any] = [
            "has_more": true,
            "data": [["id": "evt_1"], ["id": "evt_2"]]
        ]
        XCTAssertEqual(StripeProvider.nextCursor(payload: stripe), "evt_2")

        let renderLogs: [String: Any] = [
            "hasMore": true,
            "nextStartTime": "2026-08-06T10:01:00Z",
            "nextEndTime": "2026-08-06T10:02:00Z",
            "logs": []
        ]
        XCTAssertEqual(
            RenderProvider.logPageCursor(payload: renderLogs),
            RenderProvider.LogPageCursor(startTime: "2026-08-06T10:01:00Z", endTime: "2026-08-06T10:02:00Z")
        )

        let renderDeploys = (0..<100).map { ["cursor": "cursor_\($0)", "deploy": ["id": "dep_\($0)"]] }
        XCTAssertEqual(RenderProvider.deployPageCursor(payload: renderDeploys), "cursor_99")

        let link = #"<https://sentry.io/api/0/organizations/acme/issues/?cursor=previous>; rel="previous"; results="false", <https://sentry.io/api/0/organizations/acme/issues/?cursor=next>; rel="next"; results="true""#
        XCTAssertEqual(
            SentryProvider.nextPageURL(linkHeader: link)?.absoluteString,
            "https://sentry.io/api/0/organizations/acme/issues/?cursor=next"
        )
    }

    func testRetryDelayHonorsProviderHeaders() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "3"]
        ))
        XCTAssertEqual(APIClient.retryDelayMilliseconds(response: response, attempt: 0), 3_000)
    }

    func testExactRequestIDBuildsCrossSourceCase() {
        let now = Date()
        let events = [
            LogEvent(timestamp: now, source: .application, level: .info, title: "GET /profile", detail: "Loading profile", requestID: "req_17", route: "/profile"),
            LogEvent(timestamp: now.addingTimeInterval(1), source: .supabase, level: .error, title: "Database error 42501", detail: "permission denied for table profiles", requestID: "req_17", route: "/profile"),
            LogEvent(timestamp: now.addingTimeInterval(2), source: .sentry, level: .error, title: "ProfileBootstrapError", detail: "request failed", requestID: "req_17", route: "/profile")
        ]

        let result = SignalDetector.detect(events: events, startingNumber: 0)
        XCTAssertEqual(result.cases.count, 1)
        XCTAssertEqual(Set(result.cases[0].events.map(\.source)), Set([.application, .supabase, .sentry]))
        XCTAssertTrue(result.cases[0].events.allSatisfy { $0.correlation == .exactID })
        XCTAssertTrue(result.cases[0].findings.contains { $0.title.contains("Exact identifier") })
    }

    func testCrossSourceEvidenceUpgradesExistingFingerprintCaseWithoutDuplicate() {
        let now = Date()
        let deploy = LogEvent(
            timestamp: now,
            source: .render,
            level: .deploy,
            title: "Render deploy live",
            detail: "srv-test · abc123",
            externalID: "deploy-1",
            fingerprint: "render:deploy:deploy-1"
        )
        let renderEvents = [
            LogEvent(
                timestamp: now.addingTimeInterval(60),
                source: .render,
                level: .error,
                title: "Render service error",
                detail: "Signalcase Render verification failure request_id=req_render_1",
                requestID: "req_render_1",
                externalID: "render-log-1",
                fingerprint: "render:test-service:verification-failure"
            ),
            LogEvent(
                timestamp: now.addingTimeInterval(90),
                source: .render,
                level: .error,
                title: "Render service error",
                detail: "Signalcase Render verification failure request_id=req_render_2",
                requestID: "req_render_2",
                externalID: "render-log-2",
                fingerprint: "render:test-service:verification-failure"
            ),
            LogEvent(
                timestamp: now.addingTimeInterval(120),
                source: .render,
                level: .error,
                title: "Render service error",
                detail: "Signalcase Render verification failure request_id=req_cross_source",
                requestID: "req_cross_source",
                externalID: "render-log-3",
                fingerprint: "render:test-service:verification-failure"
            )
        ]
        let firstDetection = SignalDetector.detect(
            events: [deploy] + renderEvents,
            startingNumber: 0
        )
        XCTAssertEqual(firstDetection.cases.count, 1)
        var existing = firstDetection.cases[0]
        existing.status = .active

        let supabase = LogEvent(
            timestamp: now.addingTimeInterval(180),
            source: .supabase,
            level: .error,
            title: "Database error P0001",
            detail: "Signalcase cross-source verification failed request_id=req_cross_source",
            requestID: "req_cross_source",
            externalID: "supabase-log-1",
            fingerprint: "supabase:P0001:cross-source-verification",
            metadata: ["sqlState": "P0001", "providerSeverity": "ERROR"]
        )
        let secondDetection = SignalDetector.detect(
            events: [deploy] + renderEvents + [supabase],
            startingNumber: 1
        )
        XCTAssertEqual(secondDetection.cases.count, 2, "The detector fixture should expose the overlapping-case scenario")

        let merged = SignalDetector.merge(detected: secondDetection.cases, into: [existing])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, existing.id)
        XCTAssertEqual(merged[0].reference, existing.reference)
        XCTAssertEqual(merged[0].status, .active)
        XCTAssertEqual(merged[0].title, "Render service error")
        XCTAssertEqual(merged[0].occurrenceCount, 3)
        XCTAssertEqual(Set(merged[0].sources), Set([.render, .supabase]))
        XCTAssertEqual(merged[0].events.filter { $0.correlation == .exactID }.count, 2)
        XCTAssertEqual(merged[0].events.filter { $0.correlation == .fingerprint }.count, 2)
        XCTAssertTrue(merged[0].findings.contains { $0.title.contains("Exact identifier connects 2 sources") })
        XCTAssertEqual(
            merged[0].detectionNote,
            "2 events are ID-matched; 2 events match the error fingerprint; 1 is time-based context."
        )
        XCTAssertTrue(merged[0].findings.contains { $0.title == "First observed 1 minute after a deploy" })
    }

    func testTimeWindowContextIsNotMarkedAsProven() {
        let now = Date()
        let events = [
            LogEvent(timestamp: now, source: .render, level: .info, title: "Worker message", detail: "Nearby unrelated context"),
            LogEvent(timestamp: now.addingTimeInterval(1), source: .supabase, level: .error, title: "Database unavailable", detail: "connection timeout")
        ]

        let result = SignalDetector.detect(events: events, startingNumber: 0)
        XCTAssertEqual(result.cases.first?.events.first?.correlation, .timeWindow)
        XCTAssertEqual(result.cases.first?.detectionNote, "1 event matches the error fingerprint; 1 is time-based context.")
    }

    func testSyncDiagnosticsAccountForEveryCheckedEventAndExplainIgnoredOnes() {
        let now = Date()
        let ignoredFingerprint = "render:ignored:test"
        let events = [
            LogEvent(
                timestamp: now,
                source: .supabase,
                level: .error,
                title: "Database error 42P01",
                detail: "relation does not exist",
                metadata: ["sqlState": "42P01", "providerSeverity": "ERROR"]
            ),
            LogEvent(
                timestamp: now,
                source: .render,
                level: .info,
                title: "Render service log",
                detail: "GET /health 200",
                metadata: ["status": "200"]
            ),
            LogEvent(
                timestamp: now,
                source: .render,
                level: .error,
                title: "Known noisy failure",
                detail: "already ignored",
                fingerprint: ignoredFingerprint
            )
        ]
        let unsupported = EventDiagnostic(
            source: .stripe,
            disposition: .unsupported,
            title: "Unsupported Stripe record",
            detail: "Missing event type",
            reason: "The Stripe event was missing its event type or event ID."
        )

        let report = SignalDetector.syncReport(
            events: events,
            unsupported: [unsupported],
            ignoredFingerprints: [ignoredFingerprint],
            sources: [.supabase, .render, .stripe]
        )

        XCTAssertEqual(report.checkedCount, 4)
        XCTAssertEqual(report.failureCount, 1)
        XCTAssertEqual(report.routineCount, 2)
        XCTAssertEqual(report.unsupportedCount, 1)
        XCTAssertEqual(
            report.summary,
            "4 events checked, 1 failure, 2 routine events ignored, 1 unsupported"
        )
        XCTAssertTrue(report.diagnostics.contains { $0.reason.contains("SQLSTATE 42P01") })
        XCTAssertTrue(report.diagnostics.contains { $0.reason.contains("HTTP 200") })
        XCTAssertTrue(report.diagnostics.contains { $0.reason.contains("muted this error type") })
    }

    func testWorkspaceDecodingDefaultsNewCleanupFieldsForExistingUsers() throws {
        let workspace = PersistedWorkspace(
            cases: [],
            events: [],
            configuration: .empty
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(workspace)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "lastSyncReport")
        json.removeValue(forKey: "ignoredFingerprints")
        json.removeValue(forKey: "deletedCases")
        json.removeValue(forKey: "hasCompletedOnboarding")
        json.removeValue(forKey: "automaticSyncEnabled")
        json.removeValue(forKey: "automaticSyncIntervalMinutes")
        json.removeValue(forKey: "lastSuccessfulSyncBySource")
        json.removeValue(forKey: "processedWebhookIDs")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(PersistedWorkspace.self, from: legacyData)

        XCTAssertNil(decoded.lastSyncReport)
        XCTAssertTrue(decoded.ignoredFingerprints.isEmpty)
        XCTAssertTrue(decoded.deletedCases.isEmpty)
        XCTAssertFalse(decoded.hasCompletedOnboarding)
        XCTAssertFalse(decoded.automaticSyncEnabled)
        XCTAssertEqual(decoded.automaticSyncIntervalMinutes, 5)
        XCTAssertTrue(decoded.lastSuccessfulSyncBySource.isEmpty)
        XCTAssertTrue(decoded.processedWebhookIDs.isEmpty)
    }
}

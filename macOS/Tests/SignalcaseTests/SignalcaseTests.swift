import XCTest
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

    func testWorkflowOnlyMovesForward() {
        XCTAssertEqual(CaseStatus.new.next, .triaged)
        XCTAssertEqual(CaseStatus.triaged.next, .fixing)
        XCTAssertEqual(CaseStatus.fixing.next, .verified)
        XCTAssertNil(CaseStatus.verified.next)
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
        XCTAssertEqual(SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0).cases.count, 0)
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
        XCTAssertEqual(SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0).cases.count, 1)
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
        XCTAssertEqual(SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0).cases.count, 0)
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
        XCTAssertEqual(SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0).cases.count, 1)
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

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "func unrelated() { /* BEGIN */ }".write(
            to: root.appendingPathComponent("page.tsx"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(RepositoryMatcher.match(events: [migrated], root: root).isEmpty)
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
            projectRoot: nil,
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

    func testExactRequestIDBuildsCrossSourceCase() {
        let now = Date()
        let events = [
            LogEvent(timestamp: now, source: .application, level: .info, title: "GET /profile", detail: "Loading profile", requestID: "req_17", route: "/profile"),
            LogEvent(timestamp: now.addingTimeInterval(1), source: .supabase, level: .error, title: "Database error 42501", detail: "permission denied for table profiles", requestID: "req_17", route: "/profile"),
            LogEvent(timestamp: now.addingTimeInterval(2), source: .sentry, level: .error, title: "ProfileBootstrapError", detail: "request failed", requestID: "req_17", route: "/profile")
        ]

        let result = SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0)
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
            projectRoot: nil,
            startingNumber: 0
        )
        XCTAssertEqual(firstDetection.cases.count, 1)
        var existing = firstDetection.cases[0]
        existing.status = .triaged

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
            projectRoot: nil,
            startingNumber: 1
        )
        XCTAssertEqual(secondDetection.cases.count, 2, "The detector fixture should expose the overlapping-case scenario")

        let merged = SignalDetector.merge(detected: secondDetection.cases, into: [existing])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, existing.id)
        XCTAssertEqual(merged[0].reference, existing.reference)
        XCTAssertEqual(merged[0].status, .triaged)
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

        let result = SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0)
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
            configuration: .empty,
            projectPath: nil
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(workspace)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "lastSyncReport")
        json.removeValue(forKey: "ignoredFingerprints")
        json.removeValue(forKey: "deletedCases")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(PersistedWorkspace.self, from: legacyData)

        XCTAssertNil(decoded.lastSyncReport)
        XCTAssertTrue(decoded.ignoredFingerprints.isEmpty)
        XCTAssertTrue(decoded.deletedCases.isEmpty)
    }
}

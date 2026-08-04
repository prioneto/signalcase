import XCTest
@testable import Signalcase

final class SignalcaseTests: XCTestCase {
    func testStarterCasesCoverWorkflow() {
        XCTAssertEqual(Set(SignalCase.samples.map(\.status)), Set(CaseStatus.allCases))
    }

    func testEveryCaseHasCrossServiceEvidenceAndFindings() {
        for item in SignalCase.samples {
            XCTAssertGreaterThanOrEqual(item.events.count, 2)
            XCTAssertFalse(item.findings.isEmpty)
            XCTAssertFalse(item.reproduction.isEmpty)
        }
    }

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

    func testTimeWindowContextIsNotMarkedAsProven() {
        let now = Date()
        let events = [
            LogEvent(timestamp: now, source: .render, level: .info, title: "Worker message", detail: "Nearby unrelated context"),
            LogEvent(timestamp: now.addingTimeInterval(1), source: .supabase, level: .error, title: "Database unavailable", detail: "connection timeout")
        ]

        let result = SignalDetector.detect(events: events, projectRoot: nil, startingNumber: 0)
        XCTAssertEqual(result.cases.first?.events.first?.correlation, .timeWindow)
        XCTAssertEqual(result.cases.first?.detectionNote, "Related events are time-based context and do not prove causation.")
    }
}

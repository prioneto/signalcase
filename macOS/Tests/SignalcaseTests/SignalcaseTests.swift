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
}


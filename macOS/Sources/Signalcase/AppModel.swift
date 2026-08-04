import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var cases: [SignalCase]
    @Published var selectedCaseID: SignalCase.ID?
    @Published var filter: CaseFilter = .all
    @Published var searchText = ""
    @Published var isCapturePresented = false
    @Published var isIntegrationsPresented = false
    @Published var isCapturing = false
    @Published var toastMessage: String?
    @Published var linkedProjectURL: URL?
    @Published var integrations: [Integration] = [
        .init(source: .supabase, state: .demo, detail: "Auth, Postgres and Edge Function logs"),
        .init(source: .stripe, state: .demo, detail: "Events and webhook deliveries"),
        .init(source: .render, state: .demo, detail: "Deploys, restarts and service logs"),
        .init(source: .revenueCat, state: .available, detail: "Purchases, billing and entitlement events"),
        .init(source: .sentry, state: .available, detail: "Exceptions, releases and affected users")
    ]

    init(cases: [SignalCase] = SignalCase.samples) {
        self.cases = cases
        selectedCaseID = cases.first?.id

        let fitref = URL(fileURLWithPath: "/Users/dimitrislolis/Projects/fitref", isDirectory: true)
        if FileManager.default.fileExists(atPath: fitref.path) {
            linkedProjectURL = fitref
        }
    }

    var filteredCases: [SignalCase] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cases
            .filter { item in
                let matchesStatus = filter.status.map { item.status == $0 } ?? true
                let matchesQuery = query.isEmpty
                    || item.title.localizedCaseInsensitiveContains(query)
                    || item.reference.localizedCaseInsensitiveContains(query)
                    || item.events.contains { $0.detail.localizedCaseInsensitiveContains(query) }
                return matchesStatus && matchesQuery
            }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    var selectedCase: SignalCase? {
        guard let selectedCaseID else { return nil }
        return cases.first { $0.id == selectedCaseID }
    }

    var projectName: String {
        linkedProjectURL?.lastPathComponent ?? "No project linked"
    }

    func count(for filter: CaseFilter) -> Int {
        guard let status = filter.status else { return cases.count }
        return cases.filter { $0.status == status }.count
    }

    func select(_ item: SignalCase) {
        selectedCaseID = item.id
    }

    func advanceSelectedCase() {
        guard let selectedCaseID,
              let index = cases.firstIndex(where: { $0.id == selectedCaseID }),
              let next = cases[index].status.next else { return }
        cases[index].status = next
        showToast("Moved to \(next.title)")
    }

    func captureRecentLogs(minutes: Int, sources: Set<LogSource>, note: String) async {
        guard !isCapturing else { return }
        isCapturing = true
        try? await Task.sleep(for: .milliseconds(850))

        let now = Date()
        let requestedSources = sources.isEmpty ? Set([LogSource.supabase, .render]) : sources
        let events = demoCaptureEvents(now: now).filter { requestedSources.contains($0.source) }
        let usableEvents = events.isEmpty ? demoCaptureEvents(now: now) : events
        let nextNumber = (cases.compactMap { Int($0.reference.replacingOccurrences(of: "SIG-", with: "")) }.max() ?? 104) + 1
        let additionalContext = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let captured = SignalCase(
            id: UUID(),
            reference: "SIG-\(nextNumber)",
            title: "Profile export fails when the worker starts processing",
            summary: additionalContext.isEmpty
                ? "Signalcase grouped a failed export request, its background job, and the matching database error from the last \(minutes) minutes."
                : additionalContext,
            status: .new,
            severity: .high,
            occurrenceCount: 4,
            affectedUsers: 3,
            firstSeen: now.addingTimeInterval(-420),
            lastSeen: now.addingTimeInterval(-36),
            release: "fitref-web · 7c21d8e",
            environment: "Production",
            fingerprint: EventFingerprint.make(source: .supabase, message: "Export job failed: column profile_snapshot does not exist"),
            events: usableEvents,
            findings: [
                .init(title: "One operation across three events", detail: "Request req_export_92 links the user action, background job, and database failure.", tone: .neutral),
                .init(title: "Database schema does not match the worker", detail: "The worker queries profile_snapshot, but Postgres reports that the column does not exist.", tone: .failure),
                .init(title: "Started after release 7c21d8e", detail: "The first matching failure appeared six minutes after the latest Render deploy.", tone: .warning)
            ],
            codeReferences: [
                .init(path: "app/api/profile/export/route.ts", line: 88, reason: "Enqueues the export job"),
                .init(path: "workers/profile-export.ts", line: 47, reason: "Reads profile_snapshot")
            ],
            reproduction: [
                "Run the production schema locally without the profile_snapshot column.",
                "Open Profile and choose Export.",
                "Confirm the worker reports the same database error and the UI shows a useful failure."
            ]
        )

        cases.insert(captured, at: 0)
        selectedCaseID = captured.id
        filter = .all
        isCapturing = false
        isCapturePresented = false
        showToast("Built \(captured.reference) from \(usableEvents.count) related events")
    }

    func setIntegration(_ source: LogSource, connected: Bool) {
        guard let index = integrations.firstIndex(where: { $0.source == source }) else { return }
        integrations[index].state = connected ? .demo : .available
        showToast(connected ? "\(source.title) demo source enabled" : "\(source.title) disconnected")
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Link source project"
        panel.prompt = "Link project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            linkedProjectURL = panel.url
            showToast("Linked \(projectName)")
        }
    }

    func openCode(_ reference: CodeReference) {
        guard let linkedProjectURL else {
            showToast("Link a project before opening source")
            return
        }
        let url = linkedProjectURL.appendingPathComponent(reference.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showToast("That demo path is not present in \(projectName)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func copySelectedCase() {
        guard let item = selectedCase else { return }
        var lines = [
            "\(item.reference) · \(item.title)",
            "\(item.severity.title) · \(item.occurrenceCount) occurrences · \(item.affectedUsers) users",
            "",
            item.summary,
            "",
            "Proven findings:"
        ]
        lines.append(contentsOf: item.findings.map { "- \($0.title): \($0.detail)" })
        lines.append("")
        lines.append("Relevant code:")
        lines.append(contentsOf: item.codeReferences.map { "- \($0.path):\($0.line) — \($0.reason)" })

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        showToast("Case copied as a redacted bug packet")
    }

    private func demoCaptureEvents(now: Date) -> [LogEvent] {
        [
            .init(timestamp: now.addingTimeInterval(-422), source: .application, level: .info, title: "Profile export requested", detail: "POST /api/profile/export · user usr_318", requestID: "req_export_92"),
            .init(timestamp: now.addingTimeInterval(-421), source: .render, level: .info, title: "Background job accepted", detail: "profile-export worker · job job_781", requestID: "req_export_92"),
            .init(timestamp: now.addingTimeInterval(-419), source: .supabase, level: .error, title: "Postgres query failed", detail: "42703 · column profile_snapshot does not exist", requestID: "req_export_92"),
            .init(timestamp: now.addingTimeInterval(-418), source: .render, level: .error, title: "Export job failed", detail: "profile-export.ts:47 · retry 1 of 3", requestID: "req_export_92")
        ]
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toastMessage == message { toastMessage = nil }
        }
    }
}

extension SignalCase {
    static let samples: [SignalCase] = {
        let now = Date()
        return [
            SignalCase(
                id: UUID(uuidString: "99EA0C6C-0F35-4A41-8242-121346330101")!,
                reference: "SIG-104",
                title: "Checkout webhook fails after the latest deploy",
                summary: "Successful Stripe checkouts reach the application, but the webhook handler fails before the Supabase profile is upgraded.",
                status: .new,
                severity: .critical,
                occurrenceCount: 12,
                affectedUsers: 7,
                firstSeen: now.addingTimeInterval(-3_540),
                lastSeen: now.addingTimeInterval(-210),
                release: "fitref-web · 9f3a1b",
                environment: "Production",
                fingerprint: "supabase:null-customer-id:stripe-webhook",
                events: [
                    .init(timestamp: now.addingTimeInterval(-3_990), source: .render, level: .deploy, title: "Deploy 9f3a1b became live", detail: "fitref-web · production"),
                    .init(timestamp: now.addingTimeInterval(-3_548), source: .stripe, level: .success, title: "checkout.session.completed", detail: "€19.99 · customer cus_Q91 · event evt_731", requestID: "req_91d"),
                    .init(timestamp: now.addingTimeInterval(-3_546), source: .application, level: .info, title: "POST /api/webhooks/stripe", detail: "Received evt_731", requestID: "req_91d"),
                    .init(timestamp: now.addingTimeInterval(-3_545), source: .supabase, level: .error, title: "Profile update rejected", detail: "23502 · null value in column customer_id", requestID: "req_91d"),
                    .init(timestamp: now.addingTimeInterval(-3_544), source: .stripe, level: .error, title: "Webhook delivery returned 500", detail: "Endpoint will be retried", requestID: "req_91d")
                ],
                findings: [
                    .init(title: "Payment succeeded", detail: "Stripe completed the checkout and emitted evt_731.", tone: .good),
                    .init(title: "Application processing failed", detail: "The webhook returned 500 after Supabase rejected a null customer_id.", tone: .failure),
                    .init(title: "First seen after deploy 9f3a1b", detail: "The first matching error appeared 7 minutes after the release became live.", tone: .warning)
                ],
                codeReferences: [
                    .init(path: "app/api/webhooks/stripe/route.ts", line: 184, reason: "Writes the Stripe customer mapping"),
                    .init(path: "supabase/migrations/20260804_customer_id.sql", line: 12, reason: "Makes customer_id required")
                ],
                reproduction: [
                    "Create a Stripe test checkout for a user without stripe_customer_id.",
                    "Deliver checkout.session.completed to the webhook route.",
                    "Confirm the profile update fails with SQLSTATE 23502."
                ]
            ),
            SignalCase(
                id: UUID(uuidString: "E230A6FD-17D4-41C8-9AA3-30AE56A90202")!,
                reference: "SIG-103",
                title: "Renewed subscribers are not receiving Pro access",
                summary: "RevenueCat records a successful renewal, but the matching Supabase entitlement row remains expired for a subset of subscribers.",
                status: .triaged,
                severity: .high,
                occurrenceCount: 8,
                affectedUsers: 8,
                firstSeen: now.addingTimeInterval(-10_800),
                lastSeen: now.addingTimeInterval(-1_440),
                release: "subscription-sync · 51be22",
                environment: "Production",
                fingerprint: "revenuecat:renewal:entitlement-sync-timeout",
                events: [
                    .init(timestamp: now.addingTimeInterval(-10_810), source: .revenueCat, level: .success, title: "RENEWAL", detail: "pro_monthly · app user usr_844", requestID: "rc_evt_54"),
                    .init(timestamp: now.addingTimeInterval(-10_807), source: .application, level: .info, title: "RevenueCat webhook received", detail: "Entitlements: pro", requestID: "rc_evt_54"),
                    .init(timestamp: now.addingTimeInterval(-10_802), source: .supabase, level: .warning, title: "Edge Function timed out", detail: "subscription-sync exceeded 5 seconds", requestID: "rc_evt_54"),
                    .init(timestamp: now.addingTimeInterval(-10_780), source: .supabase, level: .error, title: "Entitlement remained expired", detail: "profiles.pro_until was not updated", requestID: "rc_evt_54")
                ],
                findings: [
                    .init(title: "RevenueCat renewed the subscription", detail: "The production renewal contains the expected Pro entitlement.", tone: .good),
                    .init(title: "The sync function timed out", detail: "All eight affected users have a five-second Edge Function timeout.", tone: .failure),
                    .init(title: "The event is safe to retry", detail: "The webhook event ID is stable and no successful write is present.", tone: .neutral)
                ],
                codeReferences: [
                    .init(path: "supabase/functions/revenuecat-webhook/index.ts", line: 96, reason: "Synchronizes pro_until")
                ],
                reproduction: [
                    "Use a renewal payload with an existing expired profile.",
                    "Delay the profile query beyond five seconds.",
                    "Verify the handler records a retryable failure instead of returning success."
                ]
            ),
            SignalCase(
                id: UUID(uuidString: "1173C01B-D117-4DB1-980D-8F6750900303")!,
                reference: "SIG-101",
                title: "Profile reads are denied after team invitations",
                summary: "Newly invited team members can authenticate, but their first profile request is rejected by an RLS policy.",
                status: .fixing,
                severity: .high,
                occurrenceCount: 31,
                affectedUsers: 14,
                firstSeen: now.addingTimeInterval(-86_400),
                lastSeen: now.addingTimeInterval(-2_900),
                release: "fitref-web · 28cc04",
                environment: "Production",
                fingerprint: "supabase:42501:team-profile-select",
                events: [
                    .init(timestamp: now.addingTimeInterval(-4_200), source: .supabase, level: .success, title: "Auth login succeeded", detail: "email provider · user usr_101", requestID: "sb_req_17"),
                    .init(timestamp: now.addingTimeInterval(-4_199), source: .application, level: .info, title: "GET /rest/v1/profiles", detail: "team_id=eq.team_28", requestID: "sb_req_17"),
                    .init(timestamp: now.addingTimeInterval(-4_198), source: .supabase, level: .error, title: "RLS policy denied profile read", detail: "42501 · permission denied for table profiles", requestID: "sb_req_17"),
                    .init(timestamp: now.addingTimeInterval(-4_197), source: .sentry, level: .error, title: "ProfileBootstrapError", detail: "14 affected users · release 28cc04", requestID: "sb_req_17")
                ],
                findings: [
                    .init(title: "Authentication is working", detail: "Every affected request follows a successful Supabase login.", tone: .good),
                    .init(title: "One RLS policy rejects invited members", detail: "Owners succeed; users with membership role=member receive SQLSTATE 42501.", tone: .failure),
                    .init(title: "Fix branch is linked", detail: "The policy update is ready for verification in the local project.", tone: .neutral)
                ],
                codeReferences: [
                    .init(path: "supabase/migrations/20260803_team_profile_policy.sql", line: 23, reason: "Restricts profile reads to owners")
                ],
                reproduction: [
                    "Invite a new member to an existing team.",
                    "Sign in with the invited account.",
                    "Load the dashboard and observe the denied profiles query."
                ]
            ),
            SignalCase(
                id: UUID(uuidString: "7E945CD3-421A-4FCF-B499-EAE0C5050404")!,
                reference: "SIG-98",
                title: "Worker processed the same payment event twice",
                summary: "A Render worker restart caused one Stripe event to be handled twice. The handler now guards on the event ID.",
                status: .verified,
                severity: .normal,
                occurrenceCount: 2,
                affectedUsers: 1,
                firstSeen: now.addingTimeInterval(-250_000),
                lastSeen: now.addingTimeInterval(-249_940),
                release: "billing-worker · 198ae0",
                environment: "Production",
                fingerprint: "stripe:duplicate-event:invoice-paid",
                events: [
                    .init(timestamp: now.addingTimeInterval(-250_000), source: .stripe, level: .success, title: "invoice.paid", detail: "evt_paid_88 delivered", requestID: "evt_paid_88"),
                    .init(timestamp: now.addingTimeInterval(-249_980), source: .render, level: .warning, title: "Worker restarted", detail: "Instance exceeded memory limit"),
                    .init(timestamp: now.addingTimeInterval(-249_940), source: .stripe, level: .warning, title: "invoice.paid retried", detail: "evt_paid_88 delivered again", requestID: "evt_paid_88"),
                    .init(timestamp: now.addingTimeInterval(-86_000), source: .application, level: .success, title: "Idempotency regression test passed", detail: "Duplicate event created one ledger row", requestID: "evt_paid_88")
                ],
                findings: [
                    .init(title: "Duplicate event ID confirmed", detail: "Both deliveries used evt_paid_88.", tone: .failure),
                    .init(title: "Idempotency guard verified", detail: "Build 198ae0 creates one ledger row when the event is delivered twice.", tone: .good)
                ],
                codeReferences: [
                    .init(path: "workers/billing.ts", line: 62, reason: "Checks processed Stripe event IDs")
                ],
                reproduction: [
                    "Deliver the same invoice.paid payload twice.",
                    "Confirm only one billing ledger row exists."
                ]
            )
        ]
    }()
}


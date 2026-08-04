import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var cases: [SignalCase]
    @Published var rawEvents: [LogEvent]
    @Published var selectedCaseID: SignalCase.ID?
    @Published var filter: CaseFilter = .all
    @Published var searchText = ""
    @Published var isCapturePresented = false
    @Published var isIntegrationsPresented = false
    @Published var isCapturing = false
    @Published var toastMessage: String?
    @Published var linkedProjectURL: URL?
    @Published var integrations: [Integration]
    @Published var configuration: ProviderConfiguration
    @Published var dataMode: DataMode = .live
    @Published var receiverStatus = "Receiver stopped"

    private var receiver: LocalEventReceiver?
    private var savedLiveCases: [SignalCase] = []
    private var savedLiveEvents: [LogEvent] = []

    init(cases suppliedCases: [SignalCase]? = nil) {
        let workspace = WorkspaceStore.load()
        let migratedEvents = workspace.events.map(SupabaseProvider.reclassifyPersisted)
        let migratedCases = workspace.cases.compactMap(Self.reclassifyPersistedCase)
        let initialCases = suppliedCases ?? migratedCases
        cases = initialCases
        rawEvents = migratedEvents
        configuration = workspace.configuration
        if let path = workspace.projectPath, FileManager.default.fileExists(atPath: path) {
            linkedProjectURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        integrations = [
            .init(source: .supabase, state: Self.connectionState(.supabase, configuration: workspace.configuration, events: migratedEvents), detail: "Auth, database and function logs"),
            .init(source: .stripe, state: Self.connectionState(.stripe, configuration: workspace.configuration, events: migratedEvents), detail: "Events and failed webhook deliveries"),
            .init(source: .render, state: Self.connectionState(.render, configuration: workspace.configuration, events: migratedEvents), detail: "Service logs, deploys and restarts"),
            .init(source: .revenueCat, state: Self.connectionState(.revenueCat, configuration: workspace.configuration, events: migratedEvents), detail: "Incoming purchase and entitlement webhooks"),
            .init(source: .sentry, state: Self.connectionState(.sentry, configuration: workspace.configuration, events: migratedEvents), detail: "Issues, stack frames and releases"),
            .init(source: .application, state: Self.connectionState(.application, configuration: workspace.configuration, events: migratedEvents), detail: "Structured events sent by your app")
        ]
        selectedCaseID = nil
        if suppliedCases == nil {
            try? WorkspaceStore.save(PersistedWorkspace(
                cases: initialCases,
                events: migratedEvents,
                configuration: workspace.configuration,
                projectPath: workspace.projectPath
            ))
        }
        startReceiver()
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

    var connectedCount: Int {
        integrations.filter { $0.state == .connected }.count
    }

    var availableSyncSources: Set<LogSource> {
        Set(integrations.filter { $0.state == .connected }.map(\.source))
    }

    func count(for filter: CaseFilter) -> Int {
        guard let status = filter.status else { return cases.count }
        return cases.filter { $0.status == status }.count
    }

    func select(_ item: SignalCase) {
        selectedCaseID = item.id
    }

    func showCaseList() {
        selectedCaseID = nil
    }

    func advanceSelectedCase() {
        guard let selectedCaseID,
              let index = cases.firstIndex(where: { $0.id == selectedCaseID }),
              let next = cases[index].status.next else { return }
        cases[index].status = next
        persist()
        showToast("Moved to \(next.title)")
    }

    func setDataMode(_ mode: DataMode) {
        guard mode != dataMode else { return }
        if mode == .demo {
            savedLiveCases = cases
            savedLiveEvents = rawEvents
            cases = SignalCase.samples
            rawEvents = []
        } else {
            cases = savedLiveCases
            rawEvents = savedLiveEvents
        }
        dataMode = mode
        selectedCaseID = nil
    }

    func syncRecentLogs(minutes: Int, sources: Set<LogSource>) async {
        guard !isCapturing else { return }
        guard dataMode == .live else {
            showToast("Switch to Live to sync provider data")
            return
        }
        let requested = sources.intersection(availableSyncSources)
        guard !requested.isEmpty else {
            isCapturePresented = false
            isIntegrationsPresented = true
            showToast("Connect at least one source first")
            return
        }
        isCapturing = true
        defer { isCapturing = false }
        let end = Date()
        let start = end.addingTimeInterval(TimeInterval(-minutes * 60))
        var incoming: [LogEvent] = []

        for source in requested.sorted(by: { $0.rawValue < $1.rawValue }) {
            updateIntegration(source, state: .syncing)
            do {
                let events = try await fetch(source: source, start: start, end: end)
                incoming.append(contentsOf: events)
                updateIntegration(source, state: .connected, count: events.count, error: nil)
            } catch {
                updateIntegration(source, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            }
        }

        ingest(incoming)
        isCapturePresented = false
        let failed = requested.filter { source in integrations.first(where: { $0.source == source })?.state == .failed }.count
        if incoming.isEmpty {
            showToast(failed > 0 ? "Sync finished with connection errors" : "No events found in that time window")
        } else {
            showToast("Checked \(incoming.count) real events and updated \(cases.count) cases")
        }
    }

    func saveConnection(
        source: LogSource,
        token: String,
        authorizationHeader: String = "",
        signingSecret: String = ""
    ) async {
        do {
            if !token.isEmpty { try CredentialStore.save(token, source: source, kind: .apiToken) }
            if !authorizationHeader.isEmpty { try CredentialStore.save(authorizationHeader, source: source, kind: .authorizationHeader) }
            if !signingSecret.isEmpty { try CredentialStore.save(signingSecret, source: source, kind: .signingSecret) }
            persist()
            if source == .revenueCat || source == .application {
                startReceiver()
                updateIntegration(source, state: .waitingForEvent)
                showToast("Waiting for the first \(source.title) event")
            } else {
                updateIntegration(source, state: .syncing)
                let events = try await fetch(source: source, start: Date().addingTimeInterval(-300), end: Date())
                updateIntegration(source, state: .connected, count: events.count, error: nil)
                if !events.isEmpty { ingest(events) }
                showToast("\(source.title) connected · \(events.count) recent events")
            }
        } catch {
            updateIntegration(source, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast("Could not connect \(source.title)")
        }
    }

    func disconnect(_ source: LogSource) {
        CredentialStore.remove(source: source)
        updateIntegration(source, state: .disconnected, count: 0, error: nil)
        showToast("\(source.title) disconnected")
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
            persist()
            showToast("Linked \(projectName)")
        }
    }

    func importLogs() {
        let panel = NSOpenPanel()
        panel.title = "Import JSON, JSONL, or a text log"
        panel.prompt = "Import logs"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }

        var events: [LogEvent] = []
        if let payload = try? JSONSerialization.jsonObject(with: data) {
            let objects = payload as? [Any] ?? [payload]
            events = objects.compactMap { try? ApplicationEventProvider.normalize($0) }
        } else if let text = String(data: data, encoding: .utf8) {
            for line in text.split(whereSeparator: \Character.isNewline) {
                if let lineData = String(line).data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: lineData),
                   let event = try? ApplicationEventProvider.normalize(object) {
                    events.append(event)
                } else {
                    let message = SecretRedactor.redact(String(line))
                    events.append(LogEvent(timestamp: Date(), source: .application, level: Self.level(for: message), title: String(message.prefix(100)), detail: message))
                }
            }
        }
        ingest(events)
        showToast(events.isEmpty ? "No readable log events found" : "Imported \(events.count) events")
    }

    func openCode(_ reference: CodeReference) {
        guard let linkedProjectURL else {
            showToast("Link a project before opening source")
            return
        }
        let url = linkedProjectURL.appendingPathComponent(reference.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showToast("That path is not present in \(projectName)")
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

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toastMessage == message { toastMessage = nil }
        }
    }

    private func fetch(source: LogSource, start: Date, end: Date) async throws -> [LogEvent] {
        let token = CredentialStore.load(source: source, kind: .apiToken) ?? ""
        switch source {
        case .supabase: return try await SupabaseProvider.fetch(configuration: configuration, token: token, start: start, end: end)
        case .stripe: return try await StripeProvider.fetch(token: token, start: start, end: end)
        case .render: return try await RenderProvider.fetch(configuration: configuration, token: token, start: start, end: end)
        case .sentry: return try await SentryProvider.fetch(configuration: configuration, token: token, start: start, end: end)
        case .revenueCat, .application:
            return rawEvents.filter { $0.source == source && $0.timestamp >= start && $0.timestamp <= end }
        }
    }

    private func ingest(_ events: [LogEvent]) {
        guard !events.isEmpty else { return }
        let redacted = events.map(Self.redacted)
        var seen = Set<String>()
        rawEvents = (rawEvents + redacted).filter { event in
            let key = event.externalID.map { "\(event.source.rawValue):\($0)" }
                ?? "\(event.source.rawValue):\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
            return seen.insert(key).inserted
        }.sorted { $0.timestamp > $1.timestamp }
        if rawEvents.count > 5_000 { rawEvents = Array(rawEvents.prefix(5_000)) }

        let next = cases.compactMap { Int($0.reference.replacingOccurrences(of: "SIG-", with: "")) }.max() ?? 0
        let detected = SignalDetector.detect(events: rawEvents, projectRoot: linkedProjectURL, startingNumber: next)
        cases = SignalDetector.merge(detected: detected.cases, into: cases.filter { !$0.isDemo })
        selectedCaseID = cases.first?.id
        filter = .all
        persist()
    }

    private func startReceiver() {
        receiver?.stop()
        let receiver = LocalEventReceiver(
            onEvent: { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    let count = self.rawEvents.filter { $0.source == event.source }.count + 1
                    self.updateIntegration(event.source, state: .connected, count: count, error: nil)
                    self.ingest([event])
                }
            },
            onState: { [weak self] state in Task { @MainActor in self?.receiverStatus = state } }
        )
        self.receiver = receiver
        do { try receiver.start(port: configuration.revenueCatPort) }
        catch { receiverStatus = "Receiver failed: \(error.localizedDescription)" }
    }

    private func updateIntegration(_ source: LogSource, state: IntegrationState, count: Int? = nil, error: String? = nil) {
        guard let index = integrations.firstIndex(where: { $0.source == source }) else { return }
        integrations[index].state = state
        if let count { integrations[index].eventCount = count }
        integrations[index].errorMessage = error
        if state == .connected { integrations[index].lastSync = Date() }
    }

    private func persist() {
        guard dataMode == .live else { return }
        let workspace = PersistedWorkspace(cases: cases, events: rawEvents, configuration: configuration, projectPath: linkedProjectURL?.path)
        do { try WorkspaceStore.save(workspace) }
        catch { showToast("Could not save workspace: \(error.localizedDescription)") }
    }

    static func connectionState(_ source: LogSource, configuration: ProviderConfiguration, events: [LogEvent]) -> IntegrationState {
        switch source {
        case .supabase: return !configuration.supabaseProjectRef.isEmpty && CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .sentry: return !configuration.sentryOrganization.isEmpty && !configuration.sentryProject.isEmpty && CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .render: return !configuration.renderOwnerID.isEmpty && !configuration.renderResourceIDs.isEmpty && CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .stripe: return CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .revenueCat, .application: return events.contains { $0.source == source } ? .connected : .disconnected
        }
    }

    private static func level(for text: String) -> EventLevel {
        let value = text.lowercased()
        if value.contains("error") || value.contains("fatal") || value.contains("exception") { return .error }
        if value.contains("warn") || value.contains("timeout") { return .warning }
        return .info
    }

    private static func redacted(_ event: LogEvent) -> LogEvent {
        LogEvent(
            id: event.id,
            timestamp: event.timestamp,
            source: event.source,
            level: event.level,
            title: SecretRedactor.redact(event.title),
            detail: SecretRedactor.redact(event.detail),
            requestID: event.requestID,
            externalID: event.externalID,
            userID: event.userID.map(SecretRedactor.redact),
            release: event.release,
            route: event.route,
            fingerprint: event.fingerprint,
            correlation: event.correlation,
            metadata: SecretRedactor.redact(event.metadata)
        )
    }

    private static func reclassifyPersistedCase(_ item: SignalCase) -> SignalCase? {
        var migrated = item
        migrated.events = item.events.map(SupabaseProvider.reclassifyPersisted)
        guard migrated.events.contains(where: SignalDetector.isCandidate) else { return nil }
        return migrated
    }
}

extension SignalCase {
    static let samples: [SignalCase] = {
        let now = Date()
        let samples = [
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
        return samples.map { sample in
            var tagged = sample
            tagged.isDemo = true
            tagged.detectionNote = "Demo case built from seeded example events."
            return tagged
        }
    }()
}

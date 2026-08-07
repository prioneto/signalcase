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
    @Published var isSettingsPresented = false
    @Published var isOnboardingPresented: Bool
    @Published var settingsSection: SettingsSection = .general
    @Published var isCapturing = false
    @Published var toastMessage: String?
    @Published var linkedProjectURL: URL?
    @Published var integrations: [Integration]
    @Published var configuration: ProviderConfiguration
    @Published var receiverStatus = "Receiver stopped"
    @Published var lastSyncReport: SyncReport?
    @Published var ignoredFingerprints: [IgnoredFingerprint]
    @Published var deletedCases: [SignalCase]
    @Published var automaticSyncEnabled: Bool
    @Published var automaticSyncIntervalMinutes: Int
    @Published var lastSuccessfulSyncBySource: [String: Date]
    @Published var cloudEmail: String?
    @Published var cloudProjectID: UUID?
    @Published var isCloudBusy = false

    private var receiver: LocalEventReceiver?
    private var automaticSyncTask: Task<Void, Never>?
    private var processedWebhookIDs: [String]
    private let cloud = SignalcaseCloud()

    init(cases suppliedCases: [SignalCase]? = nil) {
        let workspace = WorkspaceStore.load()
        let migratedEvents = workspace.events.map(SupabaseProvider.reclassifyPersisted)
        let migratedCases = workspace.cases.compactMap(Self.reclassifyPersistedCase)
        let ignored = Set(workspace.ignoredFingerprints.map(\.fingerprint))
        let projectRoot = workspace.projectPath
            .flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
        let initialCases: [SignalCase]
        if let suppliedCases {
            initialCases = suppliedCases.filter { !ignored.contains($0.fingerprint) }
        } else {
            let nextReference = migratedCases
                .compactMap { Int($0.reference.replacingOccurrences(of: "SIG-", with: "")) }
                .max() ?? 0
            let detected = SignalDetector.detect(
                events: migratedEvents,
                projectRoot: projectRoot,
                startingNumber: nextReference
            )
            initialCases = SignalDetector.merge(
                detected: detected.cases.filter { !ignored.contains($0.fingerprint) },
                into: migratedCases.filter { !ignored.contains($0.fingerprint) }
            )
        }
        cases = initialCases
        rawEvents = migratedEvents
        configuration = workspace.configuration
        linkedProjectURL = projectRoot
        lastSyncReport = workspace.lastSyncReport
        ignoredFingerprints = workspace.ignoredFingerprints
        deletedCases = workspace.deletedCases
        automaticSyncEnabled = workspace.automaticSyncEnabled
        automaticSyncIntervalMinutes = workspace.automaticSyncIntervalMinutes
        lastSuccessfulSyncBySource = workspace.lastSuccessfulSyncBySource
        processedWebhookIDs = workspace.processedWebhookIDs.isEmpty
            ? migratedEvents.compactMap(Self.webhookStoreKey)
            : workspace.processedWebhookIDs
        cloudEmail = nil
        cloudProjectID = workspace.cloudProjectID
        isOnboardingPresented = !workspace.hasCompletedOnboarding
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
                projectPath: workspace.projectPath,
                cloudProjectID: workspace.cloudProjectID,
                lastSyncReport: workspace.lastSyncReport,
                ignoredFingerprints: workspace.ignoredFingerprints,
                deletedCases: workspace.deletedCases,
                hasCompletedOnboarding: workspace.hasCompletedOnboarding,
                automaticSyncEnabled: workspace.automaticSyncEnabled,
                automaticSyncIntervalMinutes: workspace.automaticSyncIntervalMinutes,
                lastSuccessfulSyncBySource: workspace.lastSuccessfulSyncBySource,
                processedWebhookIDs: processedWebhookIDs
            ))
        }
        startReceiver()
        restartAutomaticSync()
        Task { await restoreCloudSession() }
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

    private var configuredPullSources: Set<LogSource> {
        var sources = Set([LogSource.stripe, .render, .sentry].filter { source in
            CredentialStore.load(source: source) != nil
        })
        if cloudProjectID != nil, integrations.first(where: { $0.source == .supabase })?.state == .connected {
            sources.insert(.supabase)
        }
        return sources
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

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        isSettingsPresented = true
    }

    func completeOnboarding(openConnections: Bool = false) {
        isOnboardingPresented = false
        persist()
        if openConnections { openSettings(.connections) }
    }

    func restartOnboarding() {
        isSettingsPresented = false
        isOnboardingPresented = true
        persist()
    }

    func advanceSelectedCase() {
        guard let selectedCaseID,
              let index = cases.firstIndex(where: { $0.id == selectedCaseID }),
              let next = cases[index].status.next else { return }
        cases[index].status = next
        persist()
        showToast("Moved to \(next.title)")
    }

    func syncRecentLogs(minutes: Int, sources: Set<LogSource>, automatic: Bool = false) async {
        guard !isCapturing else { return }
        let requested = sources.intersection(automatic ? configuredPullSources : availableSyncSources)
        guard !requested.isEmpty else {
            if !automatic {
                isCapturePresented = false
                openSettings(.connections)
                showToast("Connect at least one source first")
            }
            return
        }
        isCapturing = true
        defer { isCapturing = false }
        let end = Date()
        let start = end.addingTimeInterval(TimeInterval(-minutes * 60))
        var incoming: [LogEvent] = []
        var unsupported: [EventDiagnostic] = []
        var sourceErrors: [String] = []

        for source in requested.sorted(by: { $0.rawValue < $1.rawValue }) {
            updateIntegration(source, state: .syncing)
            do {
                let overlapStart = lastSuccessfulSyncBySource[source.rawValue]?.addingTimeInterval(-60)
                let sourceStart = automatic ? max(start, overlapStart ?? start) : start
                let batch = try await fetch(source: source, start: sourceStart, end: end)
                incoming.append(contentsOf: batch.events)
                unsupported.append(contentsOf: batch.unsupported)
                updateIntegration(source, state: .connected, count: batch.events.count + batch.unsupported.count, error: nil)
                lastSuccessfulSyncBySource[source.rawValue] = end
            } catch {
                let message = "\(source.title): \(SecretRedactor.redact(error.localizedDescription))"
                sourceErrors.append(message)
                updateIntegration(source, state: .failed, error: message)
            }
        }

        lastSyncReport = SignalDetector.syncReport(
            events: incoming,
            unsupported: unsupported,
            ignoredFingerprints: Set(ignoredFingerprints.map(\.fingerprint)),
            sources: requested,
            suppressedEventKeys: Set(deletedCases.flatMap {
                $0.events.filter(SignalDetector.isCandidate).map(Self.eventStoreKey)
            }),
            sourceErrors: sourceErrors
        )
        ingest(incoming)
        let failed = requested.filter { source in integrations.first(where: { $0.source == source })?.state == .failed }.count
        persist()
        if !automatic {
            if incoming.isEmpty && unsupported.isEmpty {
                showToast(failed > 0 ? "Sync finished with connection errors" : "No events found in that time window")
            } else {
                showToast(lastSyncReport?.summary ?? "Sync complete")
            }
        }
    }

    func saveConnection(
        source: LogSource,
        token: String,
        authorizationHeader: String = "",
        signingSecret: String = ""
    ) async {
        do {
            if source == .revenueCat || source == .application {
                let hasSavedAuthorization = CredentialStore.load(source: source, kind: .authorizationHeader) != nil
                guard hasSavedAuthorization || !authorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProviderError.invalidConfiguration("Add an authorization header before starting the receiver.")
                }
            }
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
                let batch = try await fetch(source: source, start: Date().addingTimeInterval(-300), end: Date())
                updateIntegration(source, state: .connected, count: batch.events.count + batch.unsupported.count, error: nil)
                if !batch.events.isEmpty { ingest(batch.events) }
                showToast("\(source.title) connected · \(batch.events.count) recent events")
            }
        } catch {
            updateIntegration(source, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast("Could not connect \(source.title)")
        }
    }

    func disconnect(_ source: LogSource) {
        if source == .supabase {
            Task { await disconnectSupabase() }
            return
        }
        CredentialStore.remove(source: source)
        lastSuccessfulSyncBySource.removeValue(forKey: source.rawValue)
        updateIntegration(source, state: .disconnected, count: 0, error: nil)
        persist()
        showToast("\(source.title) disconnected")
    }

    func updateAutomaticSync(enabled: Bool? = nil, intervalMinutes: Int? = nil) {
        if let enabled { automaticSyncEnabled = enabled }
        if let intervalMinutes { automaticSyncIntervalMinutes = max(5, intervalMinutes) }
        persist()
        restartAutomaticSync()
    }

    func deleteSelectedCase() {
        guard let selectedCaseID,
              let index = cases.firstIndex(where: { $0.id == selectedCaseID }) else { return }
        let item = cases.remove(at: index)
        if !deletedCases.contains(where: { $0.id == item.id }) { deletedCases.insert(item, at: 0) }
        let removedKeys = Set(item.events.filter(SignalDetector.isCandidate).map(Self.eventStoreKey))
        rawEvents.removeAll { removedKeys.contains(Self.eventStoreKey($0)) }
        self.selectedCaseID = nil
        persist()
        showToast("Deleted this case only · A new occurrence can return")
    }

    func ignoreSelectedFingerprint() {
        guard let item = selectedCase else { return }
        if !ignoredFingerprints.contains(where: { $0.fingerprint == item.fingerprint }) {
            ignoredFingerprints.insert(
                IgnoredFingerprint(fingerprint: item.fingerprint, title: item.title, ignoredAt: Date()),
                at: 0
            )
        }
        let removed = cases.filter { $0.fingerprint == item.fingerprint }
        for item in removed where !deletedCases.contains(where: { $0.id == item.id }) {
            deletedCases.insert(item, at: 0)
        }
        cases.removeAll { $0.fingerprint == item.fingerprint }
        selectedCaseID = nil
        persist()
        showToast("Muted this error type · Future matches will be hidden")
    }

    func restoreDeletedCase(_ id: SignalCase.ID) {
        guard let index = deletedCases.firstIndex(where: { $0.id == id }) else { return }
        let item = deletedCases.remove(at: index)
        ignoredFingerprints.removeAll { $0.fingerprint == item.fingerprint }
        if !cases.contains(where: { $0.id == item.id }) { cases.append(item) }
        mergeRawEvents(item.events)
        persist()
        showToast("Restored \(item.reference)")
    }

    func restoreFingerprint(_ fingerprint: String) {
        ignoredFingerprints.removeAll { $0.fingerprint == fingerprint }
        let restoring = deletedCases.filter { $0.fingerprint == fingerprint }
        deletedCases.removeAll { $0.fingerprint == fingerprint }
        for item in restoring where !cases.contains(where: { $0.id == item.id }) {
            cases.append(item)
            mergeRawEvents(item.events)
        }
        redetectCases()
        persist()
        showToast("Error type unmuted")
    }

    func clearLocalData() {
        cases = []
        rawEvents = []
        deletedCases = []
        ignoredFingerprints = []
        lastSyncReport = nil
        lastSuccessfulSyncBySource = [:]
        processedWebhookIDs = []
        selectedCaseID = nil
        filter = .all
        persist()
        showToast("Cleared local cases, events, and activity history")
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
            if cloudEmail != nil { Task { await linkCloudProject() } }
        }
    }

    var isSignedIn: Bool { cloudEmail != nil }

    func signInToSignalcase() async {
        guard !isCloudBusy else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            cloudEmail = try await cloud.signIn()
            if linkedProjectURL != nil { await linkCloudProject() }
            showToast("Signed in to Signalcase")
        } catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func signOutOfSignalcase() async {
        guard !isCloudBusy else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do { try await cloud.signOut() }
        catch { showToast(SecretRedactor.redact(error.localizedDescription)) }
        cloudEmail = nil
        cloudProjectID = nil
        updateIntegration(.supabase, state: .disconnected, count: 0, error: nil)
        persist()
    }

    func connectSupabase() async {
        guard !isCloudBusy else { return }
        guard !configuration.supabaseProjectRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Enter your Supabase project reference first")
            return
        }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            if cloudEmail == nil { cloudEmail = try await cloud.signIn() }
            if cloudProjectID == nil { try await bootstrapCloudProject() }
            guard let cloudProjectID else { throw SignalcaseCloudError.server("Link a local project folder first.") }
            updateIntegration(.supabase, state: .syncing)
            try await cloud.connectSupabase(
                projectID: cloudProjectID,
                externalProjectRef: configuration.supabaseProjectRef
            )
            await refreshSupabaseConnection()
            persist()
            showToast("Supabase connected")
        } catch {
            updateIntegration(.supabase, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func disconnectSupabase() async {
        guard let cloudProjectID else { return }
        do { try await cloud.disconnectSupabase(projectID: cloudProjectID) }
        catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
            return
        }
        updateIntegration(.supabase, state: .disconnected, count: 0, error: nil)
        lastSuccessfulSyncBySource.removeValue(forKey: LogSource.supabase.rawValue)
        persist()
        showToast("Supabase disconnected")
    }

    func cancelCloudAuthentication() {
        cloud.cancelPendingBrowserFlow()
    }

    func handleDeepLink(_ url: URL) {
        Task {
            if let email = await cloud.handle(url) {
                cloudEmail = email
                if linkedProjectURL != nil { await linkCloudProject() }
                showToast("Signed in to Signalcase")
            }
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
        var unsupported: [EventDiagnostic] = []
        if let payload = try? JSONSerialization.jsonObject(with: data) {
            let objects = payload as? [Any] ?? [payload]
            for object in objects {
                if let event = try? ApplicationEventProvider.normalize(object) {
                    events.append(event)
                } else {
                    unsupported.append(EventDiagnostic(
                        source: .application,
                        disposition: .unsupported,
                        title: "Unsupported imported record",
                        detail: "The record was not imported.",
                        reason: "Application events must be JSON objects with recognizable log fields."
                    ))
                }
            }
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
        lastSyncReport = SignalDetector.syncReport(
            events: events,
            unsupported: unsupported,
            ignoredFingerprints: Set(ignoredFingerprints.map(\.fingerprint)),
            sources: [.application]
        )
        ingest(events)
        persist()
        showToast(lastSyncReport?.summary ?? "No readable log events found")
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

    private func fetch(source: LogSource, start: Date, end: Date) async throws -> ProviderBatch {
        let token = CredentialStore.load(source: source, kind: .apiToken) ?? ""
        switch source {
        case .supabase:
            guard let cloudProjectID else { throw SignalcaseCloudError.signedOut }
            let payload = try await cloud.syncSupabase(projectID: cloudProjectID, start: start, end: end)
            return ProviderBatch(events: SupabaseProvider.normalize(payload))
        case .stripe: return try await StripeProvider.fetchBatch(token: token, start: start, end: end)
        case .render: return try await RenderProvider.fetchBatch(configuration: configuration, token: token, start: start, end: end)
        case .sentry: return try await SentryProvider.fetchBatch(configuration: configuration, token: token, start: start, end: end)
        case .revenueCat, .application:
            return ProviderBatch(events: rawEvents.filter { $0.source == source && $0.timestamp >= start && $0.timestamp <= end })
        }
    }

    private func ingest(_ events: [LogEvent]) {
        guard !events.isEmpty else { return }
        let tombstones = Set(deletedCases.flatMap { $0.events.filter(SignalDetector.isCandidate).map(Self.eventStoreKey) })
        let redacted = events.map(Self.redacted).filter { !tombstones.contains(Self.eventStoreKey($0)) }
        var seen = Set<String>()
        // Prefer the freshly normalized version when a provider returns an event we already stored.
        rawEvents = (redacted + rawEvents).filter { event in
            let key = event.externalID.map { "\(event.source.rawValue):\($0)" }
                ?? "\(event.source.rawValue):\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
            return seen.insert(key).inserted
        }.sorted { $0.timestamp > $1.timestamp }
        if rawEvents.count > 5_000 { rawEvents = Array(rawEvents.prefix(5_000)) }

        let next = cases.compactMap { Int($0.reference.replacingOccurrences(of: "SIG-", with: "")) }.max() ?? 0
        let detected = SignalDetector.detect(events: rawEvents, projectRoot: linkedProjectURL, startingNumber: next)
        let ignored = Set(ignoredFingerprints.map(\.fingerprint))
        cases = SignalDetector.merge(detected: detected.cases.filter { !ignored.contains($0.fingerprint) }, into: cases)
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
                    if let key = Self.webhookStoreKey(event), self.processedWebhookIDs.contains(key) {
                        return
                    }
                    if let key = Self.webhookStoreKey(event) {
                        self.processedWebhookIDs.insert(key, at: 0)
                        if self.processedWebhookIDs.count > 10_000 {
                            self.processedWebhookIDs = Array(self.processedWebhookIDs.prefix(10_000))
                        }
                    }
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

    private func restartAutomaticSync() {
        automaticSyncTask?.cancel()
        automaticSyncTask = nil
        guard automaticSyncEnabled else { return }
        let interval = max(5, automaticSyncIntervalMinutes)
        automaticSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval * 60)) }
                catch { return }
                guard let self else { return }
                let pullSources = self.configuredPullSources
                guard !pullSources.isEmpty else { continue }
                await self.syncRecentLogs(
                    minutes: max(15, interval * 2),
                    sources: pullSources,
                    automatic: true
                )
            }
        }
    }

    private func updateIntegration(_ source: LogSource, state: IntegrationState, count: Int? = nil, error: String? = nil) {
        guard let index = integrations.firstIndex(where: { $0.source == source }) else { return }
        integrations[index].state = state
        if let count { integrations[index].eventCount = count }
        integrations[index].errorMessage = error
        if state == .connected { integrations[index].lastSync = Date() }
    }

    private func persist() {
        let workspace = PersistedWorkspace(
            cases: cases,
            events: rawEvents,
            configuration: configuration,
            projectPath: linkedProjectURL?.path,
            cloudProjectID: cloudProjectID,
            lastSyncReport: lastSyncReport,
            ignoredFingerprints: ignoredFingerprints,
            deletedCases: deletedCases,
            hasCompletedOnboarding: !isOnboardingPresented,
            automaticSyncEnabled: automaticSyncEnabled,
            automaticSyncIntervalMinutes: automaticSyncIntervalMinutes,
            lastSuccessfulSyncBySource: lastSuccessfulSyncBySource,
            processedWebhookIDs: processedWebhookIDs
        )
        do { try WorkspaceStore.save(workspace) }
        catch { showToast("Could not save workspace: \(error.localizedDescription)") }
    }

    static func connectionState(_ source: LogSource, configuration: ProviderConfiguration, events: [LogEvent]) -> IntegrationState {
        switch source {
        case .supabase: return .disconnected
        case .sentry: return !configuration.sentryOrganization.isEmpty && !configuration.sentryProject.isEmpty && CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .render: return !configuration.renderOwnerID.isEmpty && !configuration.renderResourceIDs.isEmpty && CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .stripe: return CredentialStore.load(source: source) != nil ? .connected : .disconnected
        case .revenueCat, .application: return events.contains { $0.source == source } ? .connected : .disconnected
        }
    }

    private func restoreCloudSession() async {
        cloudEmail = await cloud.restoreSession()
        guard cloudEmail != nil else { return }
        if cloudProjectID == nil, linkedProjectURL != nil { await linkCloudProject() }
        await refreshSupabaseConnection()
    }

    private func linkCloudProject() async {
        do {
            try await bootstrapCloudProject()
            persist()
        } catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    private func bootstrapCloudProject() async throws {
        guard let linkedProjectURL else {
            throw SignalcaseCloudError.server("Choose a project folder first.")
        }
        cloudProjectID = try await cloud.bootstrapProject(name: linkedProjectURL.lastPathComponent).id
    }

    private func refreshSupabaseConnection() async {
        guard let cloudProjectID else { return }
        do {
            let status = try await cloud.connectionStatus(projectID: cloudProjectID)
            if let projectRef = status.externalProjectRef, configuration.supabaseProjectRef.isEmpty {
                configuration.supabaseProjectRef = projectRef
            }
            switch status.state {
            case "connected": updateIntegration(.supabase, state: .connected, error: nil)
            case "connecting": updateIntegration(.supabase, state: .syncing, error: nil)
            case "error": updateIntegration(.supabase, state: .failed, error: status.error)
            default: updateIntegration(.supabase, state: .disconnected, error: nil)
            }
        } catch {
            updateIntegration(.supabase, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
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

    private func mergeRawEvents(_ events: [LogEvent]) {
        var seen = Set(rawEvents.map(Self.eventStoreKey))
        rawEvents.append(contentsOf: events.filter { seen.insert(Self.eventStoreKey($0)).inserted })
        rawEvents.sort { $0.timestamp > $1.timestamp }
    }

    private func redetectCases() {
        let next = (cases + deletedCases)
            .compactMap { Int($0.reference.replacingOccurrences(of: "SIG-", with: "")) }
            .max() ?? 0
        let detected = SignalDetector.detect(events: rawEvents, projectRoot: linkedProjectURL, startingNumber: next)
        let ignored = Set(ignoredFingerprints.map(\.fingerprint))
        cases = SignalDetector.merge(detected: detected.cases.filter { !ignored.contains($0.fingerprint) }, into: cases)
    }

    private static func eventStoreKey(_ event: LogEvent) -> String {
        event.externalID.map { "\(event.source.rawValue):external:\($0)" }
            ?? "\(event.source.rawValue):\(event.timestamp.timeIntervalSince1970):\(event.fingerprint)"
    }

    private static func webhookStoreKey(_ event: LogEvent) -> String? {
        guard event.source == .revenueCat || event.source == .application,
              let externalID = event.externalID else { return nil }
        return "\(event.source.rawValue):\(externalID)"
    }

    private static func reclassifyPersistedCase(_ item: SignalCase) -> SignalCase? {
        var migrated = item
        migrated.events = item.events.map(SupabaseProvider.reclassifyPersisted)
        guard migrated.events.contains(where: SignalDetector.isCandidate) else { return nil }
        return migrated
    }
}

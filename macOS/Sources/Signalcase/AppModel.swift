import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var cases: [SignalCase]
    @Published var rawEvents: [LogEvent]
    @Published var selectedCaseID: SignalCase.ID?
    @Published var filter: CaseFilter = .new
    @Published var searchText = ""
    @Published var isCapturePresented = false
    @Published var isSettingsPresented = false
    @Published var isFeedbackPresented = false
    @Published var isOnboardingPresented: Bool
    @Published var settingsSection: SettingsSection = .general
    @Published var isCapturing = false
    @Published var toastMessage: String?
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
    @Published var isCloudAuthenticated = false
    @Published var cloudProjectID: UUID?
    @Published var cloudProjects: [CloudProject] = []
    @Published var supabaseProjects: [SupabaseProjectOption] = []
    @Published var selectedSupabaseProject: SupabaseProjectOption?
    @Published var isChangingSupabaseProject = false
    @Published var githubRepositories: [GitHubRepositoryOption] = []
    @Published var selectedGitHubRepository: GitHubRepositoryOption?
    @Published var isChangingGitHubRepository = false
    @Published var renderWorkspaces: [RenderWorkspaceOption] = []
    @Published var renderServices: [RenderServiceOption] = []
    @Published var selectedRenderWorkspaceID: String?
    @Published var selectedRenderServiceIDs: Set<String> = []
    @Published var isRenderDiscoveryActive = false
    @Published var productionApplicationEndpoint = ""
    @Published var productionApplicationAuthorization = ""
    @Published var isCloudBusy = false
    @Published var isRestoringCloudSession = true

    private var receiver: LocalEventReceiver?
    private var automaticSyncTask: Task<Void, Never>?
    private var processedWebhookIDs: [String]
    private let cloud = SignalcaseCloud()

    init(cases suppliedCases: [SignalCase]? = nil) {
        let workspace = WorkspaceStore.load()
        let migratedEvents = workspace.events.map(SupabaseProvider.reclassifyPersisted)
        let migratedCases = workspace.cases.compactMap(Self.reclassifyPersistedCase)
        let ignored = Set(workspace.ignoredFingerprints.map(\.fingerprint))
        let initialCases: [SignalCase]
        if let suppliedCases {
            initialCases = suppliedCases.filter { !ignored.contains($0.fingerprint) }
        } else {
            let nextReference = migratedCases
                .compactMap { Int($0.reference.replacingOccurrences(of: "SIG-", with: "")) }
                .max() ?? 0
            let detected = SignalDetector.detect(events: migratedEvents, startingNumber: nextReference)
            initialCases = SignalDetector.merge(
                detected: detected.cases.filter { !ignored.contains($0.fingerprint) },
                into: migratedCases.filter { !ignored.contains($0.fingerprint) }
            )
        }
        cases = initialCases
        rawEvents = migratedEvents
        configuration = workspace.configuration
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
        let savedApplicationAuthorization = CredentialStore.load(
            source: .application,
            kind: .authorizationHeader,
            projectID: workspace.cloudProjectID
        ) ?? ""
        productionApplicationAuthorization = savedApplicationAuthorization.hasPrefix("Bearer sc_live_")
            ? savedApplicationAuthorization
            : ""
        isOnboardingPresented = !workspace.hasCompletedOnboarding
        if let projectID = workspace.cloudProjectID { CredentialStore.migrateLegacyCredentials(to: projectID) }
        let hasApplicationCredential = CredentialStore.load(
            source: .application,
            kind: .authorizationHeader,
            projectID: workspace.cloudProjectID
        ) != nil
        let hasApplicationEvents = migratedEvents.contains { $0.source == .application }
        integrations = [
            .init(source: .supabase, state: Self.connectionState(.supabase, configuration: workspace.configuration, events: migratedEvents), detail: "Auth, database and function logs"),
            .init(source: .github, state: .disconnected, detail: "Repository context and failed Actions runs"),
            .init(source: .render, state: Self.connectionState(.render, configuration: workspace.configuration, events: migratedEvents, projectID: workspace.cloudProjectID), detail: "Service logs, deploys and restarts"),
            .init(
                source: .application,
                state: hasApplicationEvents ? .connected : (hasApplicationCredential ? .waitingForEvent : .disconnected),
                detail: "Errors and request context emitted by your code"
            )
        ]
        selectedCaseID = nil
        if suppliedCases == nil {
            try? WorkspaceStore.save(PersistedWorkspace(
                cases: initialCases,
                events: migratedEvents,
                configuration: workspace.configuration,
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
        if hasApplicationCredential { startReceiver() }
        restartAutomaticSync()
        Task { await restoreCloudSession() }
    }

    var filteredCases: [SignalCase] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cases
            .filter { item in
                let matchesStatus = filter.contains(item.status)
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
        cloudProjects.first(where: { $0.id == cloudProjectID })?.name ?? "No project selected"
    }

    var connectedCount: Int {
        integrations.filter { $0.state == .connected }.count
    }

    var availableSyncSources: Set<LogSource> {
        Set(integrations.filter { [.connected, .waitingForEvent].contains($0.state) }.map(\.source))
    }

    private var configuredPullSources: Set<LogSource> {
        var sources = Set<LogSource>()
        if !configuration.renderOwnerID.isEmpty,
           !configuration.renderResourceIDs.isEmpty,
           CredentialStore.load(source: .render, projectID: cloudProjectID) != nil {
            sources.insert(.render)
        }
        if cloudProjectID != nil, integrations.first(where: { $0.source == .supabase })?.state == .connected {
            sources.insert(.supabase)
        }
        if cloudProjectID != nil, integrations.first(where: { $0.source == .github })?.state == .connected {
            sources.insert(.github)
        }
        if cloudProjectID != nil,
           [.connected, .waitingForEvent].contains(integrations.first(where: { $0.source == .application })?.state) {
            sources.insert(.application)
        }
        return sources
    }

    var renderServicesForSelectedWorkspace: [RenderServiceOption] {
        guard let selectedRenderWorkspaceID else { return [] }
        return renderServices.filter { $0.ownerID == selectedRenderWorkspaceID }
    }

    func count(for filter: CaseFilter) -> Int {
        cases.filter { filter.contains($0.status) }.count
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

    func openFeedback() {
        isFeedbackPresented = true
    }

    func submitFeedback(
        kind: FeedbackKind,
        subject: String,
        message: String,
        includeAppDetails: Bool
    ) async throws {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = includeAppDetails
            ? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
            : "Not included"
        let build = includeAppDetails
            ? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
            : "Not included"
        let sourceNames = includeAppDetails
            ? integrations.filter { $0.state == .connected }.map(\.source.title).sorted()
            : []

        try await cloud.submitFeedback(
            projectID: includeAppDetails ? cloudProjectID : nil,
            kind: kind,
            subject: cleanSubject,
            message: cleanMessage,
            appVersion: version,
            appBuild: build,
            osVersion: includeAppDetails ? ProcessInfo.processInfo.operatingSystemVersionString : "Not included",
            projectName: includeAppDetails ? projectName : "Not included",
            connectedSources: sourceNames
        )
        isFeedbackPresented = false
        showToast("Feedback sent · thank you")
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

    func performSelectedCaseAction() {
        guard let selectedID = selectedCaseID,
              let index = cases.firstIndex(where: { $0.id == selectedID }) else { return }
        let current = cases[index].status
        let destination = current.actionDestination
        cases[index].status = destination
        persist()
        switch destination {
        case .new:
            showToast("Moved to New")
        case .active:
            showToast(current == .resolved ? "Case reopened in Active" : "Added to Active")
        case .resolved:
            filter = .new
            selectedCaseID = nil
            showToast("Resolved · it will reopen if the error returns")
        }
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

    func discoverRender(token: String = "") async {
        guard let cloudProjectID else {
            showToast("Create or select a Signalcase project first")
            return
        }
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = cleanToken.isEmpty
            ? CredentialStore.load(source: .render, kind: .apiToken, projectID: cloudProjectID) ?? ""
            : cleanToken

        isCloudBusy = true
        updateIntegration(.render, state: .syncing, error: nil)
        defer { isCloudBusy = false }
        do {
            let discovery = try await RenderProvider.discover(token: credential)
            try CredentialStore.save(credential, source: .render, kind: .apiToken, projectID: cloudProjectID)
            renderWorkspaces = discovery.workspaces
            renderServices = discovery.services
            isRenderDiscoveryActive = true

            let savedIDs = Set(configuration.renderResourceIDs
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            let savedServices = discovery.services.filter {
                $0.ownerID == configuration.renderOwnerID && savedIDs.contains($0.id)
            }
            if !savedServices.isEmpty {
                selectedRenderWorkspaceID = configuration.renderOwnerID
                selectedRenderServiceIDs = Set(savedServices.map(\.id))
                updateIntegration(.render, state: .connected, error: nil)
                showToast("Render services refreshed")
                return
            }

            let recommended = RenderProvider.recommendedServices(
                from: discovery.services,
                projectName: projectName
            )
            if let ownerID = recommended.first?.ownerID, !recommended.isEmpty {
                selectedRenderWorkspaceID = ownerID
                selectedRenderServiceIDs = Set(recommended.map(\.id))
                try await applyRenderSelection(token: credential)
                return
            }

            selectedRenderWorkspaceID = discovery.workspaces.count == 1
                ? discovery.workspaces.first?.id
                : nil
            selectedRenderServiceIDs = []
            updateIntegration(.render, state: .available, error: nil)
            showToast(discovery.services.isEmpty
                ? "No Render services with runtime logs were found"
                : "Choose the services that belong to \(projectName)")
        } catch {
            updateIntegration(.render, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast("Could not discover Render services")
        }
    }

    func selectRenderWorkspace(_ workspaceID: String) {
        guard workspaceID != selectedRenderWorkspaceID else { return }
        selectedRenderWorkspaceID = workspaceID
        let services = renderServices.filter { $0.ownerID == workspaceID }
        selectedRenderServiceIDs = services.count == 1 ? Set(services.map(\.id)) : []
    }

    func toggleRenderService(_ serviceID: String) {
        guard renderServicesForSelectedWorkspace.contains(where: { $0.id == serviceID }) else { return }
        if selectedRenderServiceIDs.contains(serviceID) {
            selectedRenderServiceIDs.remove(serviceID)
        } else {
            selectedRenderServiceIDs.insert(serviceID)
        }
    }

    func connectSelectedRenderServices() async {
        guard let cloudProjectID,
              let token = CredentialStore.load(source: .render, kind: .apiToken, projectID: cloudProjectID) else {
            showToast("Paste a Render API key first")
            return
        }
        isCloudBusy = true
        updateIntegration(.render, state: .syncing, error: nil)
        defer { isCloudBusy = false }
        do {
            try await applyRenderSelection(token: token)
        } catch {
            updateIntegration(.render, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast("Could not connect the selected Render services")
        }
    }

    func cancelRenderDiscovery() {
        renderWorkspaces = []
        renderServices = []
        selectedRenderWorkspaceID = nil
        selectedRenderServiceIDs = []
        isRenderDiscoveryActive = false
        let state = Self.connectionState(
            .render,
            configuration: configuration,
            events: rawEvents,
            projectID: cloudProjectID
        )
        updateIntegration(.render, state: state, error: nil)
    }

    private func applyRenderSelection(token: String) async throws {
        guard let ownerID = selectedRenderWorkspaceID else {
            throw ProviderError.invalidConfiguration("Choose a Render workspace.")
        }
        let selectedServices = renderServices
            .filter { $0.ownerID == ownerID && selectedRenderServiceIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !selectedServices.isEmpty else {
            throw ProviderError.invalidConfiguration("Choose at least one Render service.")
        }
        guard let workspace = renderWorkspaces.first(where: { $0.id == ownerID }) else {
            throw ProviderError.invalidConfiguration("The selected Render workspace is no longer available.")
        }

        let previousConfiguration = configuration
        configuration.renderOwnerID = ownerID
        configuration.renderResourceIDs = selectedServices.map(\.id).joined(separator: ",")
        configuration.renderWorkspaceName = workspace.name
        configuration.renderSelectedServices = selectedServices
        persist()

        do {
            let batch = try await RenderProvider.fetchBatch(
                configuration: configuration,
                token: token,
                start: Date().addingTimeInterval(-300),
                end: Date()
            )
            updateIntegration(.render, state: .connected, count: batch.events.count + batch.unsupported.count, error: nil)
            if !batch.events.isEmpty { ingest(batch.events) }
            renderWorkspaces = []
            renderServices = []
            selectedRenderWorkspaceID = nil
            selectedRenderServiceIDs = []
            isRenderDiscoveryActive = false
            persist()
            showToast("Render connected · \(selectedServices.count) service\(selectedServices.count == 1 ? "" : "s")")
        } catch {
            configuration = previousConfiguration
            persist()
            throw error
        }
    }

    func saveConnection(
        source: LogSource,
        token: String,
        authorizationHeader: String = "",
        signingSecret: String = ""
    ) async {
        if source == .render {
            await discoverRender(token: token)
            return
        }
        do {
            guard let cloudProjectID else {
                throw SignalcaseCloudError.server("Create or select a Signalcase project first.")
            }
            if source == .application {
                isCloudBusy = true
                defer { isCloudBusy = false }
                let setup = try await cloud.connectApplicationLogs(projectID: cloudProjectID)
                try CredentialStore.save(
                    setup.authorization,
                    source: .application,
                    kind: .authorizationHeader,
                    projectID: cloudProjectID
                )
                productionApplicationEndpoint = setup.endpoint.absoluteString
                productionApplicationAuthorization = setup.authorization
                startReceiver()
                updateIntegration(.application, state: .waitingForEvent, error: nil)
                persist()
                showToast("Production receiver created · copy the secret now")
                return
            }
            if source == .revenueCat {
                let hasSavedAuthorization = CredentialStore.load(source: source, kind: .authorizationHeader, projectID: cloudProjectID) != nil
                guard hasSavedAuthorization || !authorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProviderError.invalidConfiguration("Add an authorization header before starting the receiver.")
                }
            }
            if !token.isEmpty { try CredentialStore.save(token, source: source, kind: .apiToken, projectID: cloudProjectID) }
            if !authorizationHeader.isEmpty { try CredentialStore.save(authorizationHeader, source: source, kind: .authorizationHeader, projectID: cloudProjectID) }
            if !signingSecret.isEmpty { try CredentialStore.save(signingSecret, source: source, kind: .signingSecret, projectID: cloudProjectID) }
            persist()
            if source == .revenueCat {
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
        if source == .github {
            Task { await disconnectGitHub() }
            return
        }
        if source == .application {
            Task { await disconnectApplicationLogs() }
            return
        }
        CredentialStore.remove(source: source, projectID: cloudProjectID)
        if source == .render {
            configuration.renderOwnerID = ""
            configuration.renderResourceIDs = ""
            configuration.renderWorkspaceName = nil
            configuration.renderSelectedServices = nil
            renderWorkspaces = []
            renderServices = []
            selectedRenderWorkspaceID = nil
            selectedRenderServiceIDs = []
            isRenderDiscoveryActive = false
        }
        if source == .application {
            receiver?.stop()
            receiver = nil
            receiverStatus = "Receiver stopped"
        }
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
        filter = .new
        persist()
        showToast("Cleared local cases, events, and activity history")
    }

    var isSignedIn: Bool { isCloudAuthenticated }

    func createProject(named value: String) async -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showToast("Enter a project name")
            return false
        }
        guard !isCloudBusy else { return false }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            if !isSignedIn {
                let identity = try await cloud.signIn()
                cloudEmail = identity.email
                isCloudAuthenticated = true
            }
            let project = try await cloud.bootstrapProject(name: name)
            if !cloudProjects.contains(where: { $0.id == project.id }) {
                cloudProjects.append(project)
                cloudProjects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            selectProject(project, preserveCurrentDataIfUnassigned: cloudProjectID == nil)
            showToast("Created \(project.name)")
            return true
        } catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
            return false
        }
    }

    func selectProject(_ project: CloudProject) {
        selectProject(project, preserveCurrentDataIfUnassigned: false)
    }

    private func selectProject(_ project: CloudProject, preserveCurrentDataIfUnassigned: Bool) {
        guard project.id != cloudProjectID else { return }
        let hadNoProject = cloudProjectID == nil
        persist()
        if preserveCurrentDataIfUnassigned && hadNoProject {
            cloudProjectID = project.id
            configuration.supabaseProjectRef = ""
            selectedSupabaseProject = nil
            isChangingSupabaseProject = false
            selectedGitHubRepository = nil
            isChangingGitHubRepository = false
            persist()
        } else {
            applyProjectWorkspace(WorkspaceStore.load(projectID: project.id), projectID: project.id)
        }
        selectedCaseID = nil
        filter = .new
        Task {
            await refreshSupabaseConnection()
            await refreshGitHubConnection()
            await refreshApplicationConnection()
        }
        showToast("Switched to \(project.name)")
    }

    func signInToSignalcase() async {
        guard !isCloudBusy else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            let identity = try await cloud.signIn()
            cloudEmail = identity.email
            isCloudAuthenticated = true
            await refreshCloudProjects()
            await refreshSupabaseConnection()
            await refreshGitHubConnection()
            await refreshApplicationConnection()
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
        isCloudAuthenticated = false
        cloudProjects = []
        supabaseProjects = []
        selectedSupabaseProject = nil
        isChangingSupabaseProject = false
        githubRepositories = []
        selectedGitHubRepository = nil
        isChangingGitHubRepository = false
        isSettingsPresented = false
        isCapturePresented = false
        isFeedbackPresented = false
        updateIntegration(.supabase, state: .disconnected, count: 0, error: nil)
        updateIntegration(.github, state: .disconnected, count: 0, error: nil)
        persist()
    }

    func connectSupabase() async {
        guard !isCloudBusy else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        isChangingSupabaseProject = false
        do {
            if !isSignedIn {
                let identity = try await cloud.signIn()
                cloudEmail = identity.email
                isCloudAuthenticated = true
            }
            if cloudProjects.isEmpty { await refreshCloudProjects() }
            guard let cloudProjectID else { throw SignalcaseCloudError.server("Create or select a Signalcase project first.") }
            updateIntegration(.supabase, state: .syncing)
            let projects = try await cloud.authorizeSupabase(projectID: cloudProjectID)
            guard !projects.isEmpty else {
                throw SignalcaseCloudError.server("This Supabase account has no accessible projects.")
            }
            if projects.count == 1, let onlyProject = projects.first {
                try await finishSupabaseConnection(onlyProject, signalcaseProjectID: cloudProjectID)
            } else {
                supabaseProjects = projects
                updateIntegration(.supabase, state: .available, error: nil)
                showToast("Choose the Supabase project to connect")
            }
        } catch {
            supabaseProjects = []
            updateIntegration(.supabase, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func changeSupabaseProject() async {
        guard !isCloudBusy, let cloudProjectID else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            let projects = try await cloud.listSupabaseProjects(projectID: cloudProjectID)
            guard !projects.isEmpty else {
                throw SignalcaseCloudError.server("This Supabase account has no accessible projects.")
            }
            supabaseProjects = projects
            isChangingSupabaseProject = true
            updateIntegration(.supabase, state: .connected, error: nil)
        } catch {
            updateIntegration(.supabase, state: .connected, error: SecretRedactor.redact(error.localizedDescription))
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func chooseSupabaseProject(_ project: SupabaseProjectOption) async {
        guard !isCloudBusy, let cloudProjectID else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            updateIntegration(.supabase, state: .syncing, error: nil)
            try await finishSupabaseConnection(project, signalcaseProjectID: cloudProjectID)
        } catch {
            updateIntegration(
                .supabase,
                state: isChangingSupabaseProject ? .connected : .failed,
                error: SecretRedactor.redact(error.localizedDescription)
            )
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func cancelSupabaseProjectSelection() {
        supabaseProjects = []
        if isChangingSupabaseProject {
            isChangingSupabaseProject = false
            updateIntegration(.supabase, state: .connected, error: nil)
            return
        }
        updateIntegration(.supabase, state: .disconnected, error: nil)
        Task { await disconnectSupabase() }
    }

    private func finishSupabaseConnection(
        _ project: SupabaseProjectOption,
        signalcaseProjectID: UUID
    ) async throws {
        let selected = try await cloud.selectSupabaseProject(
            projectID: signalcaseProjectID,
            projectRef: project.ref
        )
        configuration.supabaseProjectRef = selected.ref
        selectedSupabaseProject = selected
        supabaseProjects = []
        isChangingSupabaseProject = false
        await refreshSupabaseConnection()
        persist()
        showToast("Connected \(selected.name)")
    }

    func disconnectSupabase() async {
        guard let cloudProjectID else { return }
        do { try await cloud.disconnectSupabase(projectID: cloudProjectID) }
        catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
            return
        }
        updateIntegration(.supabase, state: .disconnected, count: 0, error: nil)
        supabaseProjects = []
        selectedSupabaseProject = nil
        isChangingSupabaseProject = false
        configuration.supabaseProjectRef = ""
        lastSuccessfulSyncBySource.removeValue(forKey: LogSource.supabase.rawValue)
        persist()
        showToast("Supabase disconnected")
    }

    func connectGitHub() async {
        guard !isCloudBusy else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        isChangingGitHubRepository = false
        do {
            if !isSignedIn {
                let identity = try await cloud.signIn()
                cloudEmail = identity.email
                isCloudAuthenticated = true
            }
            if cloudProjects.isEmpty { await refreshCloudProjects() }
            guard let cloudProjectID else {
                throw SignalcaseCloudError.server("Create or select a Signalcase project first.")
            }
            updateIntegration(.github, state: .syncing, error: nil)
            let repositories = try await cloud.authorizeGitHub(projectID: cloudProjectID)
            guard !repositories.isEmpty else {
                throw SignalcaseCloudError.server("The GitHub App has no repository access. Add a repository in GitHub and reconnect.")
            }
            if let recommended = recommendedGitHubRepository(in: repositories) {
                try await finishGitHubConnection(recommended, signalcaseProjectID: cloudProjectID)
            } else {
                githubRepositories = repositories
                updateIntegration(.github, state: .available, error: nil)
                showToast("Choose the GitHub repository to connect")
            }
        } catch {
            githubRepositories = []
            updateIntegration(.github, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func changeGitHubRepository() async {
        guard !isCloudBusy, let cloudProjectID else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            let repositories = try await cloud.listGitHubRepositories(projectID: cloudProjectID)
            guard !repositories.isEmpty else {
                throw SignalcaseCloudError.server("The GitHub App has no accessible repositories.")
            }
            githubRepositories = repositories
            isChangingGitHubRepository = true
            updateIntegration(.github, state: .connected, error: nil)
        } catch {
            updateIntegration(.github, state: .connected, error: SecretRedactor.redact(error.localizedDescription))
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func chooseGitHubRepository(_ repository: GitHubRepositoryOption) async {
        guard !isCloudBusy, let cloudProjectID else { return }
        isCloudBusy = true
        defer { isCloudBusy = false }
        do {
            updateIntegration(.github, state: .syncing, error: nil)
            try await finishGitHubConnection(repository, signalcaseProjectID: cloudProjectID)
        } catch {
            updateIntegration(
                .github,
                state: isChangingGitHubRepository ? .connected : .failed,
                error: SecretRedactor.redact(error.localizedDescription)
            )
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    func cancelGitHubRepositorySelection() {
        githubRepositories = []
        if isChangingGitHubRepository {
            isChangingGitHubRepository = false
            updateIntegration(.github, state: .connected, error: nil)
            return
        }
        updateIntegration(.github, state: .disconnected, error: nil)
        Task { await disconnectGitHub() }
    }

    func disconnectGitHub() async {
        guard let cloudProjectID else { return }
        do { try await cloud.disconnectGitHub(projectID: cloudProjectID) }
        catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
            return
        }
        githubRepositories = []
        selectedGitHubRepository = nil
        isChangingGitHubRepository = false
        lastSuccessfulSyncBySource.removeValue(forKey: LogSource.github.rawValue)
        updateIntegration(.github, state: .disconnected, count: 0, error: nil)
        persist()
        showToast("GitHub disconnected")
    }

    private func finishGitHubConnection(
        _ repository: GitHubRepositoryOption,
        signalcaseProjectID: UUID
    ) async throws {
        let selected = try await cloud.selectGitHubRepository(
            projectID: signalcaseProjectID,
            repositoryID: repository.id
        )
        selectedGitHubRepository = selected
        githubRepositories = []
        isChangingGitHubRepository = false
        await refreshGitHubConnection()
        persist()
        showToast("Connected \(selected.fullName)")
    }

    private func recommendedGitHubRepository(
        in repositories: [GitHubRepositoryOption]
    ) -> GitHubRepositoryOption? {
        if repositories.count == 1 { return repositories.first }
        let renderNames = Set((configuration.renderSelectedServices ?? []).compactMap {
            $0.repositoryName?.lowercased()
        })
        guard !renderNames.isEmpty else { return nil }
        let matches = repositories.filter { renderNames.contains($0.name.lowercased()) }
        return matches.count == 1 ? matches.first : nil
    }

    func cancelCloudAuthentication() {
        cloud.cancelPendingBrowserFlow()
    }

    func handleDeepLink(_ url: URL) {
        Task {
            if let identity = await cloud.handle(url) {
                cloudEmail = identity.email
                isCloudAuthenticated = true
                await refreshCloudProjects()
                await refreshApplicationConnection()
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
        let token = CredentialStore.load(source: source, kind: .apiToken, projectID: cloudProjectID) ?? ""
        switch source {
        case .supabase:
            guard let cloudProjectID else { throw SignalcaseCloudError.signedOut }
            let payload = try await cloud.syncSupabase(projectID: cloudProjectID, start: start, end: end)
            return ProviderBatch(events: SupabaseProvider.normalize(payload))
        case .github:
            guard let cloudProjectID else { throw SignalcaseCloudError.signedOut }
            let payload = try await cloud.syncGitHub(projectID: cloudProjectID, start: start, end: end)
            return ProviderBatch(events: GitHubProvider.normalize(payload))
        case .stripe: return try await StripeProvider.fetchBatch(token: token, start: start, end: end)
        case .render: return try await RenderProvider.fetchBatch(configuration: configuration, token: token, start: start, end: end)
        case .sentry: return try await SentryProvider.fetchBatch(configuration: configuration, token: token, start: start, end: end)
        case .application:
            guard let cloudProjectID else { throw SignalcaseCloudError.signedOut }
            let payload = try await cloud.syncApplicationLogs(projectID: cloudProjectID, start: start, end: end)
            return ProviderBatch(events: rows(from: payload).compactMap {
                try? ApplicationEventProvider.normalize($0)
            })
        case .revenueCat:
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
        let detected = SignalDetector.detect(events: rawEvents, startingNumber: next)
        let ignored = Set(ignoredFingerprints.map(\.fingerprint))
        cases = SignalDetector.merge(detected: detected.cases.filter { !ignored.contains($0.fingerprint) }, into: cases)
        selectedCaseID = cases.first?.id
        filter = .new
        persist()
    }

    private func startReceiver() {
        receiver?.stop()
        let receiver = LocalEventReceiver(
            applicationAuthorization: CredentialStore.load(
                source: .application,
                kind: .authorizationHeader,
                projectID: cloudProjectID
            ),
            revenueCatAuthorization: CredentialStore.load(
                source: .revenueCat,
                kind: .authorizationHeader,
                projectID: cloudProjectID
            ),
            revenueCatSigningSecret: CredentialStore.load(
                source: .revenueCat,
                kind: .signingSecret,
                projectID: cloudProjectID
            ),
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

    static func connectionState(
        _ source: LogSource,
        configuration: ProviderConfiguration,
        events: [LogEvent],
        projectID: UUID? = nil
    ) -> IntegrationState {
        switch source {
        case .supabase, .github: return .disconnected
        case .sentry: return !configuration.sentryOrganization.isEmpty && !configuration.sentryProject.isEmpty && CredentialStore.load(source: source, projectID: projectID) != nil ? .connected : .disconnected
        case .render: return !configuration.renderOwnerID.isEmpty && !configuration.renderResourceIDs.isEmpty && CredentialStore.load(source: source, projectID: projectID) != nil ? .connected : .disconnected
        case .stripe: return CredentialStore.load(source: source, projectID: projectID) != nil ? .connected : .disconnected
        case .revenueCat, .application: return events.contains { $0.source == source } ? .connected : .disconnected
        }
    }

    private func restoreCloudSession() async {
        defer { isRestoringCloudSession = false }
        guard let identity = await cloud.restoreSession() else {
            cloudEmail = nil
            isCloudAuthenticated = false
            return
        }
        cloudEmail = identity.email
        isCloudAuthenticated = true
        await refreshCloudProjects()
        await refreshSupabaseConnection()
        await refreshGitHubConnection()
        await refreshApplicationConnection()
    }

    private func refreshCloudProjects() async {
        do {
            cloudProjects = try await cloud.listProjects().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if let selectedID = cloudProjectID,
               cloudProjects.contains(where: { $0.id == selectedID }) {
                return
            }
            guard let first = cloudProjects.first else {
                cloudProjectID = nil
                isOnboardingPresented = true
                persist()
                return
            }
            selectProject(first, preserveCurrentDataIfUnassigned: cloudProjectID == nil)
        } catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
        }
    }

    private func applyProjectWorkspace(_ workspace: PersistedWorkspace, projectID: UUID) {
        receiver?.stop()
        receiver = nil
        cases = workspace.cases.compactMap(Self.reclassifyPersistedCase)
        rawEvents = workspace.events.map(SupabaseProvider.reclassifyPersisted)
        configuration = workspace.configuration
        cloudProjectID = projectID
        supabaseProjects = []
        selectedSupabaseProject = nil
        isChangingSupabaseProject = false
        githubRepositories = []
        selectedGitHubRepository = nil
        isChangingGitHubRepository = false
        renderWorkspaces = []
        renderServices = []
        selectedRenderWorkspaceID = nil
        selectedRenderServiceIDs = []
        isRenderDiscoveryActive = false
        productionApplicationEndpoint = ""
        let savedApplicationAuthorization = CredentialStore.load(
            source: .application,
            kind: .authorizationHeader,
            projectID: projectID
        ) ?? ""
        productionApplicationAuthorization = savedApplicationAuthorization.hasPrefix("Bearer sc_live_")
            ? savedApplicationAuthorization
            : ""
        lastSyncReport = workspace.lastSyncReport
        ignoredFingerprints = workspace.ignoredFingerprints
        deletedCases = workspace.deletedCases
        automaticSyncEnabled = workspace.automaticSyncEnabled
        automaticSyncIntervalMinutes = workspace.automaticSyncIntervalMinutes
        lastSuccessfulSyncBySource = workspace.lastSuccessfulSyncBySource
        processedWebhookIDs = workspace.processedWebhookIDs
        let hasApplicationCredential = CredentialStore.load(source: .application, kind: .authorizationHeader, projectID: projectID) != nil
        integrations = [
            .init(source: .supabase, state: .disconnected, detail: "Auth, database and function logs"),
            .init(source: .github, state: .disconnected, detail: "Repository context and failed Actions runs"),
            .init(source: .render, state: Self.connectionState(.render, configuration: configuration, events: rawEvents, projectID: projectID), detail: "Service logs, deploys and restarts"),
            .init(
                source: .application,
                state: rawEvents.contains { $0.source == .application } ? .connected : (hasApplicationCredential ? .waitingForEvent : .disconnected),
                detail: "Errors and request context emitted by your code"
            )
        ]
        if hasApplicationCredential { startReceiver() }
        restartAutomaticSync()
        persist()
    }

    private func refreshSupabaseConnection() async {
        guard let cloudProjectID else { return }
        do {
            let status = try await cloud.connectionStatus(projectID: cloudProjectID)
            if let selectedProject = status.selectedProject {
                selectedSupabaseProject = selectedProject
            } else if let projectRef = status.externalProjectRef,
                      selectedSupabaseProject?.ref != projectRef {
                let accessibleProjects = try? await cloud.listSupabaseProjects(projectID: cloudProjectID)
                selectedSupabaseProject = accessibleProjects?.first(where: { $0.ref == projectRef }) ?? SupabaseProjectOption(
                    ref: projectRef,
                    name: projectRef,
                    organizationSlug: nil,
                    region: nil,
                    status: nil
                )
            } else if status.externalProjectRef == nil {
                selectedSupabaseProject = nil
            }
            if let projectRef = status.externalProjectRef,
               configuration.supabaseProjectRef != projectRef {
                configuration.supabaseProjectRef = projectRef
                persist()
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

    private func refreshGitHubConnection() async {
        guard let cloudProjectID else { return }
        do {
            let status = try await cloud.githubConnectionStatus(projectID: cloudProjectID)
            selectedGitHubRepository = status.selectedRepository
            switch status.state {
            case "connected": updateIntegration(.github, state: .connected, error: nil)
            case "connecting": updateIntegration(.github, state: .available, error: nil)
            case "error": updateIntegration(.github, state: .failed, error: status.error)
            default: updateIntegration(.github, state: .disconnected, error: nil)
            }
        } catch {
            updateIntegration(.github, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
        }
    }

    private func refreshApplicationConnection() async {
        guard let cloudProjectID else { return }
        do {
            let status = try await cloud.applicationConnectionStatus(projectID: cloudProjectID)
            productionApplicationEndpoint = status.endpoint.absoluteString
            let savedApplicationAuthorization = CredentialStore.load(
                source: .application,
                kind: .authorizationHeader,
                projectID: cloudProjectID
            ) ?? ""
            productionApplicationAuthorization = savedApplicationAuthorization.hasPrefix("Bearer sc_live_")
                ? savedApplicationAuthorization
                : ""
            switch status.state {
            case "connected":
                updateIntegration(
                    .application,
                    state: status.lastEventAt == nil ? .waitingForEvent : .connected,
                    error: nil
                )
            case "error": updateIntegration(.application, state: .failed, error: status.error)
            default: updateIntegration(.application, state: .disconnected, error: nil)
            }
        } catch {
            updateIntegration(.application, state: .failed, error: SecretRedactor.redact(error.localizedDescription))
        }
    }

    private func disconnectApplicationLogs() async {
        guard let cloudProjectID else { return }
        do { try await cloud.disconnectApplicationLogs(projectID: cloudProjectID) }
        catch {
            showToast(SecretRedactor.redact(error.localizedDescription))
            return
        }
        CredentialStore.remove(source: .application, projectID: cloudProjectID)
        receiver?.stop()
        receiver = nil
        receiverStatus = "Receiver stopped"
        productionApplicationAuthorization = ""
        lastSuccessfulSyncBySource.removeValue(forKey: LogSource.application.rawValue)
        updateIntegration(.application, state: .disconnected, count: 0, error: nil)
        persist()
        showToast("Application Logs disconnected")
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
        let detected = SignalDetector.detect(events: rawEvents, startingNumber: next)
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

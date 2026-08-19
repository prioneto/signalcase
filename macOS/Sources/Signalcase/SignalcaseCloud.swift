import AppKit
import Foundation
import Supabase

enum SignalcaseCloudError: LocalizedError {
    case notConfigured(String)
    case signedOut
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let value): value
        case .signedOut: "Sign in to Signalcase first."
        case .invalidResponse: "Signalcase Cloud returned an unreadable response."
        case .server(let value): value
        }
    }
}

struct CloudProject: Codable, Identifiable, Hashable {
    let id: UUID
    let workspaceId: UUID
    let name: String
    let slug: String
}

struct CloudIdentity {
    let email: String?
}

struct CloudConnectionStatus: Codable {
    let state: String
    let externalProjectRef: String?
    let selectedProject: SupabaseProjectOption?
    let connectedAt: String?
    let lastSyncedAt: String?
    let error: String?
}

struct SupabaseProjectOption: Codable, Identifiable, Hashable {
    let ref: String
    let name: String
    let organizationSlug: String?
    let region: String?
    let status: String?

    var id: String { ref }
}

struct GitHubRepositoryOption: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let fullName: String
    let owner: String?
    let htmlUrl: URL
    let defaultBranch: String
    let isPrivate: Bool
}

struct GitHubConnectionStatus: Codable {
    let state: String
    let accountLogin: String?
    let selectedRepository: GitHubRepositoryOption?
    let connectedAt: String?
    let lastSyncedAt: String?
    let error: String?
}

struct ApplicationConnectionStatus: Codable {
    let state: String
    let endpoint: URL
    let connectedAt: String?
    let lastEventAt: String?
    let error: String?
}

struct ApplicationConnectionSetup: Codable {
    let state: String
    let endpoint: URL
    let authorization: String
    let connectedAt: String?
}

struct CloudTeamMember: Codable, Identifiable, Hashable {
    let userId: UUID
    let email: String
    let role: String
    let joinedAt: String
    let isCurrentUser: Bool

    var id: UUID { userId }
}

struct CloudInvitation: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let role: String
    let expiresAt: String
    let createdAt: String?
}

struct CloudTeam: Codable {
    let workspaceId: UUID
    let currentRole: String
    let members: [CloudTeamMember]
    let invitations: [CloudInvitation]
    let memberLimit: Int
}

struct CloudBillingState: Codable {
    let configured: Bool
    let enforcementEnabled: Bool
    let access: Bool
    let plan: String
    let status: String
    let provider: String
    let trialEndsAt: String?
    let currentPeriodEndsAt: String?
    let cancelAtPeriodEnd: Bool
    let memberLimit: Int
    let projectLimit: Int
    let eventRetentionDays: Int
    let canManage: Bool
}

private struct CloudProjectEnvelope: Codable { let project: CloudProject }
private struct CloudProjectsEnvelope: Codable { let projects: [CloudProject] }
private struct CloudCasesEnvelope: Codable { let cases: [SignalCase] }
private struct CloudCaseEnvelope: Codable { let `case`: SignalCase }
private struct CloudCasesSubmission: Encodable {
    let projectID: UUID
    let cases: [SignalCase]

    enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case cases
    }
}
private struct CloudCaseStatusSubmission: Encodable {
    let projectID: UUID
    let caseID: UUID
    let status: CaseStatus

    enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case caseID = "caseId"
        case status
    }
}
private struct CloudTeamMutation: Encodable {
    let projectID: UUID
    let userID: UUID?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case userID = "userId"
        case role
    }
}
private struct CloudInvitationSubmission: Encodable {
    let projectID: UUID
    let email: String?
    let role: String?
    let invitationID: UUID?

    enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case email, role
        case invitationID = "invitationId"
    }
}
private struct CloudInvitationCreated: Codable {
    struct Invitation: Codable { let id: UUID; let email: String; let role: String; let expiresAt: String; let url: URL }
    let invitation: Invitation
}
private struct BillingURLEnvelope: Codable { let url: URL }
private struct DeleteEnvelope: Codable { let deleted: Bool?; let leftWorkspace: Bool?; let revoked: Bool? }
private struct SupabaseProjectsEnvelope: Codable { let projects: [SupabaseProjectOption] }
private struct SupabaseSelectionEnvelope: Codable {
    let state: String
    let externalProjectRef: String
    let project: SupabaseProjectOption
}
private struct GitHubRepositoriesEnvelope: Codable { let repositories: [GitHubRepositoryOption] }
private struct GitHubSelectionEnvelope: Codable {
    let state: String
    let repository: GitHubRepositoryOption
}
private struct GitHubRepositorySelection: Encodable {
    let projectID: String
    let repositoryID: Int64

    enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case repositoryID = "repositoryId"
    }
}
private struct StateEnvelope: Codable { let state: String }
private struct AuthorizationEnvelope: Codable { let authorizationUrl: URL }
private struct APIErrorEnvelope: Codable { let error: String }

private struct FeedbackSubmission: Encodable {
    let projectID: UUID?
    let kind: String
    let subject: String
    let message: String
    let contactEmail: String?
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let projectName: String
    let connectedSources: [String]

    enum CodingKeys: String, CodingKey {
        case kind, subject, message
        case projectID = "project_id"
        case contactEmail = "contact_email"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case osVersion = "os_version"
        case projectName = "project_name"
        case connectedSources = "connected_sources"
    }
}

@MainActor
final class SignalcaseCloud {
    private let client: SupabaseClient?
    private let serverURL: URL?
    private var pendingBrowserCallback: PendingBrowserCallback?
    private var browserTimeoutTask: Task<Void, Never>?

    init(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let supabaseURLValue = environment["SIGNALCASE_SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SignalcaseSupabaseURL") as? String
        let publishableKey = environment["SIGNALCASE_SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "SignalcaseSupabasePublishableKey") as? String
        let serverURLValue = environment["SIGNALCASE_CLOUD_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SignalcaseCloudURL") as? String

        serverURL = serverURLValue.flatMap(URL.init(string:))
        if let supabaseURLValue,
           let supabaseURL = URL(string: supabaseURLValue),
           let publishableKey,
           !publishableKey.isEmpty {
            client = SupabaseClient(
                supabaseURL: supabaseURL,
                supabaseKey: publishableKey,
                options: SupabaseClientOptions(
                    auth: .init(
                        storage: KeychainLocalStorage(service: "app.signalcase.auth"),
                        redirectToURL: URL(string: "signalcase://auth/callback"),
                        storageKey: "app.signalcase.auth"
                    )
                )
            )
        } else {
            client = nil
        }
    }

    var currentEmail: String? { client?.auth.currentUser?.email }

    func restoreSession() async -> CloudIdentity? {
        guard let client else { return nil }
        guard let session = try? await client.auth.session else { return nil }
        return CloudIdentity(email: session.user.email)
    }

    func signIn() async throws -> CloudIdentity {
        guard let client else {
            throw SignalcaseCloudError.notConfigured("This build is missing its Signalcase Cloud settings.")
        }
        let authorizationURL = try client.auth.getOAuthSignInURL(
            provider: .github,
            redirectTo: URL(string: "signalcase://auth/callback")
        )
        let callbackURL = try await openInDefaultBrowser(
            authorizationURL,
            expectedCallbackHost: "auth"
        )
        let session = try await client.auth.session(from: callbackURL)
        return CloudIdentity(email: session.user.email)
    }

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut(scope: .local)
    }

    func bootstrapProject(name: String, workspaceID: UUID? = nil) async throws -> CloudProject {
        let slug = Self.slug(from: name)
        struct Submission: Encodable {
            let name: String
            let slug: String
            let workspaceID: UUID?
            enum CodingKeys: String, CodingKey { case name, slug; case workspaceID = "workspaceId" }
        }
        let envelope: CloudProjectEnvelope = try await request(
            path: "/api/native/project",
            method: "POST",
            body: Submission(name: name, slug: slug, workspaceID: workspaceID)
        )
        return envelope.project
    }

    func listProjects() async throws -> [CloudProject] {
        let envelope: CloudProjectsEnvelope = try await request(
            path: "/api/native/project",
            method: "GET",
            body: Optional<[String: String]>.none
        )
        return envelope.projects
    }

    func sharedCases(projectID: UUID) async throws -> [SignalCase] {
        let envelope: CloudCasesEnvelope = try await request(
            path: "/api/cases?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
        return envelope.cases
    }

    func syncSharedCases(projectID: UUID, cases: [SignalCase]) async throws -> [SignalCase] {
        let envelope: CloudCasesEnvelope = try await request(
            path: "/api/cases",
            method: "POST",
            body: CloudCasesSubmission(projectID: projectID, cases: cases)
        )
        return envelope.cases
    }

    func updateCaseStatus(projectID: UUID, caseID: UUID, status: CaseStatus) async throws -> SignalCase {
        let envelope: CloudCaseEnvelope = try await request(
            path: "/api/cases/status",
            method: "PATCH",
            body: CloudCaseStatusSubmission(projectID: projectID, caseID: caseID, status: status)
        )
        return envelope.case
    }

    func deleteCase(projectID: UUID, caseID: UUID) async throws {
        let _: DeleteEnvelope = try await request(
            path: "/api/cases",
            method: "DELETE",
            body: ["projectId": projectID.uuidString, "caseId": caseID.uuidString]
        )
    }

    func restoreCase(projectID: UUID, caseID: UUID) async throws {
        let _: DeleteEnvelope = try await request(
            path: "/api/cases",
            method: "PUT",
            body: ["projectId": projectID.uuidString, "caseId": caseID.uuidString]
        )
    }

    func team(projectID: UUID) async throws -> CloudTeam {
        try await request(
            path: "/api/team?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
    }

    func invite(projectID: UUID, email: String, role: String) async throws -> URL {
        let result: CloudInvitationCreated = try await request(
            path: "/api/team/invitations",
            method: "POST",
            body: CloudInvitationSubmission(projectID: projectID, email: email, role: role, invitationID: nil)
        )
        return result.invitation.url
    }

    func revokeInvitation(projectID: UUID, invitationID: UUID) async throws {
        let _: DeleteEnvelope = try await request(
            path: "/api/team/invitations",
            method: "DELETE",
            body: CloudInvitationSubmission(projectID: projectID, email: nil, role: nil, invitationID: invitationID)
        )
    }

    func updateMember(projectID: UUID, userID: UUID, role: String) async throws -> CloudTeam {
        try await request(
            path: "/api/team",
            method: "PATCH",
            body: CloudTeamMutation(projectID: projectID, userID: userID, role: role)
        )
    }

    func removeMember(projectID: UUID, userID: UUID) async throws -> CloudTeam? {
        let data = try await requestData(
            path: "/api/team",
            method: "DELETE",
            body: CloudTeamMutation(projectID: projectID, userID: userID, role: nil)
        )
        return try? makeDecoder().decode(CloudTeam.self, from: data)
    }

    func billing(projectID: UUID) async throws -> CloudBillingState {
        try await request(
            path: "/api/billing/status?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
    }

    func checkoutURL(projectID: UUID) async throws -> URL {
        let envelope: BillingURLEnvelope = try await request(
            path: "/api/billing/checkout",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
        return envelope.url
    }

    func billingPortalURL(projectID: UUID) async throws -> URL {
        let envelope: BillingURLEnvelope = try await request(
            path: "/api/billing/portal",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
        return envelope.url
    }

    func deleteProject(projectID: UUID) async throws {
        let _: DeleteEnvelope = try await request(
            path: "/api/native/project",
            method: "DELETE",
            body: ["projectId": projectID.uuidString]
        )
    }

    func deleteAccount() async throws {
        let _: DeleteEnvelope = try await request(
            path: "/api/account",
            method: "DELETE",
            body: ["confirmation": "DELETE"]
        )
    }

    func openExternalURL(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw SignalcaseCloudError.server("Could not open the default browser.")
        }
    }

    func connectionStatus(projectID: UUID) async throws -> CloudConnectionStatus {
        try await request(
            path: "/api/integrations/supabase/status?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
    }

    func authorizeSupabase(projectID: UUID) async throws -> [SupabaseProjectOption] {
        let envelope: AuthorizationEnvelope = try await request(
            path: "/api/integrations/supabase/session",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
        let callback = try await openInDefaultBrowser(
            envelope.authorizationUrl,
            expectedCallbackHost: "integration"
        )
        let values = Self.queryValues(from: callback)
        guard values["status"] == "authorized" else {
            throw SignalcaseCloudError.server(values["message"] ?? "Supabase authorization was cancelled.")
        }
        return try await listSupabaseProjects(projectID: projectID)
    }

    func listSupabaseProjects(projectID: UUID) async throws -> [SupabaseProjectOption] {
        let projects: SupabaseProjectsEnvelope = try await request(
            path: "/api/integrations/supabase/projects?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
        return projects.projects
    }

    func selectSupabaseProject(projectID: UUID, projectRef: String) async throws -> SupabaseProjectOption {
        let envelope: SupabaseSelectionEnvelope = try await request(
            path: "/api/integrations/supabase/projects",
            method: "POST",
            body: [
                "projectId": projectID.uuidString,
                "projectRef": projectRef,
            ]
        )
        guard envelope.state == "connected" else {
            throw SignalcaseCloudError.server("Supabase did not finish connecting.")
        }
        return envelope.project
    }

    func disconnectSupabase(projectID: UUID) async throws {
        let _: CloudConnectionStatus = try await request(
            path: "/api/integrations/supabase/disconnect",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
    }

    func syncSupabase(projectID: UUID, start: Date, end: Date) async throws -> Any {
        let formatter = ISO8601DateFormatter()
        let data = try await requestData(
            path: "/api/integrations/supabase/sync",
            method: "POST",
            body: [
                "projectId": projectID.uuidString,
                "start": formatter.string(from: start),
                "end": formatter.string(from: end),
            ]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] else {
            throw SignalcaseCloudError.invalidResponse
        }
        return payload
    }

    func authorizeGitHub(projectID: UUID) async throws -> [GitHubRepositoryOption] {
        let envelope: AuthorizationEnvelope = try await request(
            path: "/api/integrations/github/session",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
        let callback = try await openInDefaultBrowser(
            envelope.authorizationUrl,
            expectedCallbackHost: "integration"
        )
        let values = Self.queryValues(from: callback)
        guard values["status"] == "authorized" else {
            throw SignalcaseCloudError.server(values["message"] ?? "GitHub installation was cancelled.")
        }
        return try await listGitHubRepositories(projectID: projectID)
    }

    func githubConnectionStatus(projectID: UUID) async throws -> GitHubConnectionStatus {
        try await request(
            path: "/api/integrations/github/status?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
    }

    func listGitHubRepositories(projectID: UUID) async throws -> [GitHubRepositoryOption] {
        let envelope: GitHubRepositoriesEnvelope = try await request(
            path: "/api/integrations/github/repositories?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
        return envelope.repositories
    }

    func selectGitHubRepository(projectID: UUID, repositoryID: Int64) async throws -> GitHubRepositoryOption {
        let envelope: GitHubSelectionEnvelope = try await request(
            path: "/api/integrations/github/repositories",
            method: "POST",
            body: GitHubRepositorySelection(projectID: projectID.uuidString, repositoryID: repositoryID)
        )
        guard envelope.state == "connected" else {
            throw SignalcaseCloudError.server("GitHub did not finish connecting.")
        }
        return envelope.repository
    }

    func disconnectGitHub(projectID: UUID) async throws {
        let _: StateEnvelope = try await request(
            path: "/api/integrations/github/disconnect",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
    }

    func syncGitHub(projectID: UUID, start: Date, end: Date) async throws -> Any {
        let formatter = ISO8601DateFormatter()
        let data = try await requestData(
            path: "/api/integrations/github/sync",
            method: "POST",
            body: [
                "projectId": projectID.uuidString,
                "start": formatter.string(from: start),
                "end": formatter.string(from: end),
            ]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] else {
            throw SignalcaseCloudError.invalidResponse
        }
        return payload
    }

    func applicationConnectionStatus(projectID: UUID) async throws -> ApplicationConnectionStatus {
        try await request(
            path: "/api/integrations/application/connection?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
    }

    func connectApplicationLogs(projectID: UUID) async throws -> ApplicationConnectionSetup {
        try await request(
            path: "/api/integrations/application/connection",
            method: "POST",
            body: ["projectId": projectID.uuidString]
        )
    }

    func disconnectApplicationLogs(projectID: UUID) async throws {
        let _: ApplicationConnectionStatus = try await request(
            path: "/api/integrations/application/connection",
            method: "DELETE",
            body: ["projectId": projectID.uuidString]
        )
    }

    func syncApplicationLogs(projectID: UUID, start: Date, end: Date) async throws -> Any {
        let formatter = ISO8601DateFormatter()
        let data = try await requestData(
            path: "/api/integrations/application/sync",
            method: "POST",
            body: [
                "projectId": projectID.uuidString,
                "start": formatter.string(from: start),
                "end": formatter.string(from: end),
            ]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] else {
            throw SignalcaseCloudError.invalidResponse
        }
        return payload
    }

    func submitFeedback(
        projectID: UUID?,
        kind: FeedbackKind,
        subject: String,
        message: String,
        appVersion: String,
        appBuild: String,
        osVersion: String,
        projectName: String,
        connectedSources: [String]
    ) async throws {
        guard let client else {
            throw SignalcaseCloudError.notConfigured("This build is missing its Signalcase Cloud settings.")
        }
        let session: Session
        do { session = try await client.auth.session }
        catch { throw SignalcaseCloudError.signedOut }

        let submission = FeedbackSubmission(
            projectID: projectID,
            kind: kind.rawValue,
            subject: subject,
            message: message,
            contactEmail: session.user.email,
            appVersion: appVersion,
            appBuild: appBuild,
            osVersion: osVersion,
            projectName: projectName,
            connectedSources: connectedSources
        )
        try await client
            .from("feedback_submissions")
            .insert(submission)
            .execute()
    }

    func handle(_ url: URL) async -> CloudIdentity? {
        if pendingBrowserCallback?.expectedHost == url.host {
            finishBrowserFlow(.success(url))
            return nil
        }
        guard url.host == "auth", let client else { return nil }
        guard let session = try? await client.auth.session(from: url) else { return nil }
        return CloudIdentity(email: session.user.email)
    }

    func cancelPendingBrowserFlow() {
        finishBrowserFlow(.failure(
            SignalcaseCloudError.server("Browser authentication cancelled. Nothing was changed.")
        ))
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let data = try await requestData(path: path, method: method, body: body)
        let decoder = makeDecoder()
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw SignalcaseCloudError.invalidResponse }
    }

    private func requestData<Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Data {
        guard let client else {
            throw SignalcaseCloudError.notConfigured("This build is missing its Signalcase Cloud settings.")
        }
        guard let serverURL, let url = URL(string: path, relativeTo: serverURL) else {
            throw SignalcaseCloudError.notConfigured("This build is missing the Signalcase server URL.")
        }
        let session: Session
        do { session = try await client.auth.session }
        catch { throw SignalcaseCloudError.signedOut }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SignalcaseCloudError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error)
                ?? "Signalcase Cloud returned HTTP \(http.statusCode)."
            throw SignalcaseCloudError.server(message)
        }
        return data
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func openInDefaultBrowser(
        _ url: URL,
        expectedCallbackHost: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            if pendingBrowserCallback != nil {
                finishBrowserFlow(.failure(
                    SignalcaseCloudError.server("A newer browser authentication request replaced the previous one.")
                ))
            }
            pendingBrowserCallback = PendingBrowserCallback(
                expectedHost: expectedCallbackHost,
                continuation: continuation
            )
            guard NSWorkspace.shared.open(url) else {
                finishBrowserFlow(.failure(
                    SignalcaseCloudError.server("Could not open the default browser.")
                ))
                return
            }
            browserTimeoutTask?.cancel()
            browserTimeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
                self?.finishBrowserFlow(.failure(
                    SignalcaseCloudError.server("Browser authentication timed out. Try again when you are ready.")
                ))
            }
        }
    }

    private func finishBrowserFlow(_ result: Result<URL, Error>) {
        guard let pendingBrowserCallback else { return }
        self.pendingBrowserCallback = nil
        browserTimeoutTask?.cancel()
        browserTimeoutTask = nil
        pendingBrowserCallback.continuation.resume(with: result)
    }

    private static func slug(from value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let pieces = folded.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = pieces.filter { !$0.isEmpty }.joined(separator: "-")
        return slug.isEmpty ? "mac-project" : String(slug.prefix(80))
    }

    private static func queryValues(from url: URL) -> [String: String] {
        var values: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            values[item.name] = item.value ?? ""
        }
        return values
    }
}

private struct PendingBrowserCallback {
    let expectedHost: String
    let continuation: CheckedContinuation<URL, Error>
}

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

struct CloudProject: Codable {
    let id: UUID
    let workspaceId: UUID
    let name: String
    let slug: String
}

struct CloudConnectionStatus: Codable {
    let state: String
    let externalProjectRef: String?
    let connectedAt: String?
    let lastSyncedAt: String?
    let error: String?
}

private struct CloudProjectEnvelope: Codable { let project: CloudProject }
private struct AuthorizationEnvelope: Codable { let authorizationUrl: URL }
private struct APIErrorEnvelope: Codable { let error: String }

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

    func restoreSession() async -> String? {
        guard let client else { return nil }
        guard client.auth.currentSession != nil else { return nil }
        return (try? await client.auth.session.user.email) ?? client.auth.currentUser?.email
    }

    func signIn() async throws -> String? {
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
        return session.user.email
    }

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut(scope: .local)
    }

    func bootstrapProject(name: String) async throws -> CloudProject {
        let slug = Self.slug(from: name)
        let envelope: CloudProjectEnvelope = try await request(
            path: "/api/native/project",
            method: "POST",
            body: ["name": name, "slug": slug]
        )
        return envelope.project
    }

    func connectionStatus(projectID: UUID) async throws -> CloudConnectionStatus {
        try await request(
            path: "/api/integrations/supabase/status?projectId=\(projectID.uuidString)",
            method: "GET",
            body: Optional<[String: String]>.none
        )
    }

    func connectSupabase(projectID: UUID, externalProjectRef: String) async throws {
        let envelope: AuthorizationEnvelope = try await request(
            path: "/api/integrations/supabase/session",
            method: "POST",
            body: [
                "projectId": projectID.uuidString,
                "externalProjectRef": externalProjectRef,
            ]
        )
        let callback = try await openInDefaultBrowser(
            envelope.authorizationUrl,
            expectedCallbackHost: "integration"
        )
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard values["status"] == "connected" else {
            throw SignalcaseCloudError.server(values["message"] ?? "Supabase authorization was cancelled.")
        }
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

    func handle(_ url: URL) async -> String? {
        if pendingBrowserCallback?.expectedHost == url.host {
            finishBrowserFlow(.success(url))
            return nil
        }
        guard url.host == "auth", let client else { return nil }
        return try? await client.auth.session(from: url).user.email
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
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
            request.httpBody = try JSONEncoder().encode(body)
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
}

private struct PendingBrowserCallback {
    let expectedHost: String
    let continuation: CheckedContinuation<URL, Error>
}

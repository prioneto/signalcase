import Foundation

/// Lightweight first-party crash and error reporting. Reports are stored
/// locally first and drained to the Signalcase server in small batches, so a
/// failure to upload never loses the report. No logs, credentials, or case
/// content are ever included—only messages, short stack traces, and versions.
final class DiagnosticsReporter: @unchecked Sendable {
    static let shared = DiagnosticsReporter()

    struct PendingReport: Codable, Equatable {
        let message: String
        let stack: String?
        let context: [String: String]
        let occurredAt: Date
        let kind: String
    }

    private let defaults: UserDefaults
    private let storageKey = "signalcase.pendingDiagnostics"
    private let maximumPendingReports = 25
    private let maximumSendsPerLaunch = 10
    private let lock = NSLock()
    private var sendsThisLaunch = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Installs the uncaught exception handler once at startup. Exceptions are
    /// persisted immediately; they are delivered on the next launch.
    func install() {
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticsReporter.shared.recordException(exception)
        }
    }

    func recordException(_ exception: NSException) {
        store(
            PendingReport(
                message: SecretRedactor.redact(
                    "\(exception.name.rawValue): \(exception.reason ?? "Uncaught exception")"
                ).prefix(1_500).description,
                stack: exception.callStackSymbols.prefix(30).joined(separator: "\n"),
                context: [
                    "app_version": Self.appVersion,
                    "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                ],
                occurredAt: Date(),
                kind: "crash"
            )
        )
    }

    func capture(_ message: String, context: [String: String] = [:]) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lock.lock()
        let allowed = sendsThisLaunch < maximumSendsPerLaunch
        lock.unlock()
        guard allowed else { return }
        store(
            PendingReport(
                message: SecretRedactor.redact(message).prefix(1_500).description,
                stack: Thread.callStackSymbols.prefix(20).joined(separator: "\n"),
                context: context.merging(
                    [
                        "app_version": Self.appVersion,
                        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                    ],
                    uniquingKeysWith: { _, override in override }
                ),
                occurredAt: Date(),
                kind: "error"
            )
        )
    }

    /// Removes up to `limit` pending reports for delivery. If delivery fails,
    /// pass them back through `restore` so nothing is lost.
    func takePending(limit: Int) -> [PendingReport] {
        lock.lock()
        defer { lock.unlock() }
        let pending = loadPending()
        guard limit > 0, !pending.isEmpty else { return [] }
        let taken = Array(pending.prefix(limit))
        savePending(Array(pending.dropFirst(taken.count)))
        return taken
    }

    func restore(_ reports: [PendingReport]) {
        guard !reports.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        savePending(reports + loadPending())
    }

    /// Delivers up to five pending reports through `submit`, keeping a small
    /// per-launch budget so a failing endpoint cannot turn into a flood.
    /// Returns how many reports were delivered; undelivered reports are kept.
    @discardableResult
    func flush(using submit: (PendingReport) async throws -> Void) async -> Int {
        let remainingBudget = remainingSendBudget()
        guard remainingBudget > 0 else { return 0 }

        let batch = takePending(limit: min(5, remainingBudget))
        guard !batch.isEmpty else { return 0 }

        var deliveredCount = 0
        var firstFailedIndex: Int?
        for (index, report) in batch.enumerated() {
            do {
                try await submit(report)
                deliveredCount += 1
            } catch {
                firstFailedIndex = index
                break
            }
        }

        if let firstFailedIndex {
            restore(Array(batch[firstFailedIndex...]))
        }
        recordDelivered(count: deliveredCount)
        return deliveredCount
    }

    private func remainingSendBudget() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumSendsPerLaunch - sendsThisLaunch
    }

    private func recordDelivered(count: Int) {
        lock.lock()
        defer { lock.unlock() }
        sendsThisLaunch += count
    }

    func pendingCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadPending().count
    }

    private func store(_ report: PendingReport) {
        lock.lock()
        defer { lock.unlock() }
        var pending = loadPending()
        if pending.contains(report) { return }
        pending.append(report)
        if pending.count > maximumPendingReports {
            pending.removeFirst(pending.count - maximumPendingReports)
        }
        savePending(pending)
    }

    private func loadPending() -> [PendingReport] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingReport].self, from: data)) ?? []
    }

    private func savePending(_ reports: [PendingReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

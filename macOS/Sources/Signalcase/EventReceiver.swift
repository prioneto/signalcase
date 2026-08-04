import CryptoKit
import Foundation
import Network

final class LocalEventReceiver {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.signalcase.receiver")
    private let onEvent: @Sendable (LogEvent) -> Void
    private let onState: @Sendable (String) -> Void

    init(
        onEvent: @escaping @Sendable (LogEvent) -> Void,
        onState: @escaping @Sendable (String) -> Void
    ) {
        self.onEvent = onEvent
        self.onState = onState
    }

    func start(port: Int) throws {
        stop()
        guard let networkPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw ProviderError.invalidConfiguration("Choose a port between 1 and 65535.")
        }
        let listener = try NWListener(using: .tcp, on: networkPort)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState("Listening on localhost:\(port)")
            case .failed(let error): self?.onState("Receiver failed: \(error.localizedDescription)")
            case .cancelled: self?.onState("Receiver stopped")
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(from: connection, data: Data())
    }

    private func receive(from connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] chunk, _, complete, error in
            var collected = data
            if let chunk { collected.append(chunk) }
            if error != nil {
                connection.cancel()
            } else if complete || self?.requestIsComplete(collected) == true {
                self?.handle(collected, connection: connection)
            } else {
                self?.receive(from: connection, data: collected)
            }
        }
    }

    private func requestIsComplete(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let separator = text.range(of: "\r\n\r\n") else { return false }
        let headers = String(text[..<separator.lowerBound])
        let contentLength = headers
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let headerBytes = text[..<separator.upperBound].utf8.count
        return data.count >= headerBytes + contentLength
    }

    private func handle(_ data: Data, connection: NWConnection) {
        guard let request = HTTPRequest(data: data) else {
            respond(400, "Invalid HTTP request", to: connection)
            return
        }
        guard request.method == "POST" else {
            respond(405, "POST required", to: connection)
            return
        }

        do {
            let payload = try JSONSerialization.jsonObject(with: request.body)
            let event: LogEvent
            switch request.path {
            case "/events":
                try verifyAuthorization(request.headers["authorization"], source: .application)
                event = try ApplicationEventProvider.normalize(payload)
            case "/revenuecat":
                try verifyAuthorization(request.headers["authorization"], source: .revenueCat)
                try verifyRevenueCatSignature(request.headers["x-revenuecat-webhook-signature"], body: request.body)
                event = try RevenueCatProvider.normalizeWebhook(payload)
            default:
                respond(404, "Use POST /events or POST /revenuecat", to: connection)
                return
            }
            onEvent(event)
            respond(202, "Accepted", to: connection)
        } catch {
            respond(error is AuthorizationError ? 401 : 400, error.localizedDescription, to: connection)
        }
    }

    private func verifyAuthorization(_ received: String?, source: LogSource) throws {
        guard let expected = CredentialStore.load(source: source, kind: .authorizationHeader), !expected.isEmpty else { return }
        guard received == expected else { throw AuthorizationError.unauthorized }
    }

    private func verifyRevenueCatSignature(_ header: String?, body: Data) throws {
        guard let secret = CredentialStore.load(source: .revenueCat, kind: .signingSecret), !secret.isEmpty else { return }
        guard let header else { throw AuthorizationError.unauthorized }
        let pieces = Dictionary(uniqueKeysWithValues: header.split(separator: ",").compactMap { component -> (String, String)? in
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            return pair.count == 2 ? (pair[0], pair[1]) : nil
        })
        guard let timestamp = pieces["t"], let signature = pieces["v1"],
              let rawBody = String(data: body, encoding: .utf8) else { throw AuthorizationError.unauthorized }
        let key = SymmetricKey(data: Data(secret.utf8))
        let digest = HMAC<SHA256>.authenticationCode(for: Data("\(timestamp).\(rawBody)".utf8), using: key)
        let expected = Data(digest).map { String(format: "%02x", $0) }.joined()
        guard Data(expected.utf8) == Data(signature.lowercased().utf8) else { throw AuthorizationError.unauthorized }
    }

    private func respond(_ status: Int, _ message: String, to connection: NWConnection) {
        let reason = status == 202 ? "Accepted" : status == 401 ? "Unauthorized" : status == 404 ? "Not Found" : status == 405 ? "Method Not Allowed" : "Bad Request"
        let body = SecretRedactor.redact(message)
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

private enum AuthorizationError: LocalizedError {
    case unauthorized
    var errorDescription: String? { "Authorization did not match." }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        guard let marker = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<marker.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ").map(String.init) ?? []
        guard first.count >= 2 else { return nil }
        method = first[0]
        path = first[1].split(separator: "?").first.map(String.init) ?? first[1]
        headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        })
        body = Data(data[marker.upperBound...])
    }
}

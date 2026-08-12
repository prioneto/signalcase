import CryptoKit
import Foundation
import Network

final class LocalEventReceiver {
    private static let maximumBodyBytes = 1_048_576
    private static let maximumHeaderBytes = 65_536
    private static let maximumRequestBytes = maximumBodyBytes + maximumHeaderBytes
    private static let requestTimeout: TimeInterval = 15

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.signalcase.receiver")
    private let onEvent: @Sendable (LogEvent) -> Void
    private let onState: @Sendable (String) -> Void
    private let applicationAuthorization: String?
    private let revenueCatAuthorization: String?
    private let revenueCatSigningSecret: String?

    init(
        applicationAuthorization: String? = nil,
        revenueCatAuthorization: String? = nil,
        revenueCatSigningSecret: String? = nil,
        onEvent: @escaping @Sendable (LogEvent) -> Void,
        onState: @escaping @Sendable (String) -> Void
    ) {
        self.applicationAuthorization = applicationAuthorization
        self.revenueCatAuthorization = revenueCatAuthorization
        self.revenueCatSigningSecret = revenueCatSigningSecret
        self.onEvent = onEvent
        self.onState = onState
    }

    func start(port: Int) throws {
        stop()
        guard let networkPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw ProviderError.invalidConfiguration("Choose a port between 1 and 65535.")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: networkPort)
        let listener = try NWListener(using: parameters)
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
        let timeout = DispatchWorkItem { [weak self] in
            self?.respond(408, "Request timed out", to: connection)
        }
        queue.asyncAfter(deadline: .now() + Self.requestTimeout, execute: timeout)
        receive(from: connection, data: Data(), timeout: timeout)
    }

    private func receive(from connection: NWConnection, data: Data, timeout: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] chunk, _, complete, error in
            guard let self else {
                timeout.cancel()
                connection.cancel()
                return
            }
            var collected = data
            if let chunk { collected.append(chunk) }
            if error != nil {
                timeout.cancel()
                connection.cancel()
            } else if self.declaredContentLength(collected).map({ $0 > Self.maximumBodyBytes }) == true {
                timeout.cancel()
                self.respond(413, "Request body is too large", to: connection)
            } else if collected.count > Self.maximumRequestBytes
                        || (!collected.contains(Data("\r\n\r\n".utf8)) && collected.count > Self.maximumHeaderBytes) {
                timeout.cancel()
                self.respond(413, "Request is too large", to: connection)
            } else if complete || self.requestIsComplete(collected) {
                timeout.cancel()
                self.handle(collected, connection: connection)
            } else {
                self.receive(from: connection, data: collected, timeout: timeout)
            }
        }
    }

    private func requestIsComplete(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let separator = text.range(of: "\r\n\r\n") else { return false }
        guard let contentLength = declaredContentLength(data), contentLength >= 0 else { return false }
        let headerBytes = text[..<separator.upperBound].utf8.count
        return data.count >= headerBytes + contentLength
    }

    private func declaredContentLength(_ data: Data) -> Int? {
        guard let text = String(data: data, encoding: .utf8),
              let separator = text.range(of: "\r\n\r\n") else { return nil }
        return text[..<separator.lowerBound]
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line in
                let pieces = line.split(separator: ":", maxSplits: 1)
                guard pieces.count == 2 else { return nil }
                return Int(pieces[1].trimmingCharacters(in: .whitespaces))
            }
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
        guard request.body.count <= Self.maximumBodyBytes else {
            respond(413, "Request body is too large", to: connection)
            return
        }
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            respond(415, "Content-Type must be application/json", to: connection)
            return
        }

        do {
            switch request.path {
            case "/events":
                try WebhookSecurity.verifyAuthorization(
                    received: request.headers["authorization"],
                    expected: applicationAuthorization
                )
            case "/revenuecat":
                try WebhookSecurity.verifyAuthorization(
                    received: request.headers["authorization"],
                    expected: revenueCatAuthorization
                )
                try WebhookSecurity.verifyRevenueCatSignature(
                    header: request.headers["x-revenuecat-webhook-signature"],
                    body: request.body,
                    secret: revenueCatSigningSecret
                )
            default:
                respond(404, "Use POST /events or POST /revenuecat", to: connection)
                return
            }
            let payload = try JSONSerialization.jsonObject(with: request.body)
            let event = request.path == "/events"
                ? try ApplicationEventProvider.normalize(payload)
                : try RevenueCatProvider.normalizeWebhook(payload)
            onEvent(event)
            respond(200, "Accepted", to: connection)
        } catch {
            respond(error is AuthorizationError ? 401 : 400, error.localizedDescription, to: connection)
        }
    }

    private func respond(_ status: Int, _ message: String, to connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 408: reason = "Request Timeout"
        case 413: reason = "Content Too Large"
        case 415: reason = "Unsupported Media Type"
        default: reason = "Bad Request"
        }
        let body = SecretRedactor.redact(message)
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

enum AuthorizationError: LocalizedError {
    case unauthorized
    case staleSignature

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Authorization did not match."
        case .staleSignature: "Webhook signature is outside the five-minute replay window."
        }
    }
}

enum WebhookSecurity {
    static func verifyAuthorization(received: String?, expected: String?) throws {
        guard let expected, !expected.isEmpty, let received,
              timingSafeEqual(Data(received.utf8), Data(expected.utf8)) else {
            throw AuthorizationError.unauthorized
        }
    }

    static func verifyRevenueCatSignature(
        header: String?,
        body: Data,
        secret: String?,
        now: Date = Date(),
        tolerance: TimeInterval = 300
    ) throws {
        guard let secret, !secret.isEmpty else { return }
        guard let header else { throw AuthorizationError.unauthorized }
        let pairs = header.split(separator: ",").compactMap { component -> (String, String)? in
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            return pair.count == 2 ? (pair[0], pair[1]) : nil
        }
        var pieces: [String: String] = [:]
        for (key, value) in pairs {
            guard pieces[key] == nil else { throw AuthorizationError.unauthorized }
            pieces[key] = value
        }
        guard let timestampText = pieces["t"], let timestamp = TimeInterval(timestampText),
              let signatureText = pieces["v1"], let signature = hexData(signatureText) else {
            throw AuthorizationError.unauthorized
        }
        guard abs(now.timeIntervalSince1970 - timestamp) <= tolerance else {
            throw AuthorizationError.staleSignature
        }

        var signedPayload = Data("\(timestampText).".utf8)
        signedPayload.append(body)
        let key = SymmetricKey(data: Data(secret.utf8))
        let expected = Data(HMAC<SHA256>.authenticationCode(for: signedPayload, using: key))
        guard timingSafeEqual(expected, signature) else { throw AuthorizationError.unauthorized }
    }

    static func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }

    private static func hexData(_ value: String) -> Data? {
        let value = value.lowercased()
        guard value.count.isMultiple(of: 2) else { return nil }
        var output = Data()
        output.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<end], radix: 16) else { return nil }
            output.append(byte)
            index = end
        }
        return output
    }
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
        let pairs = lines.dropFirst().compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        var parsedHeaders: [String: String] = [:]
        for (key, value) in pairs {
            guard parsedHeaders[key] == nil else { return nil }
            parsedHeaders[key] = value
        }
        headers = parsedHeaders
        body = Data(data[marker.upperBound...])
        guard let lengthText = headers["content-length"], let length = Int(lengthText), length >= 0,
              body.count == length else { return nil }
    }
}

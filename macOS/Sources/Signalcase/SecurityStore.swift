import Foundation
import Security

enum CredentialKind: String, CaseIterable {
    case apiToken
    case authorizationHeader
    case signingSecret
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}

enum CredentialStore {
    private static let service = "app.signalcase.integrations"

    static func save(_ value: String, source: LogSource, kind: CredentialKind, projectID: UUID? = nil) throws {
        let account = account(source: source, kind: kind, projectID: projectID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }

        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }

    static func load(source: LogSource, kind: CredentialKind = .apiToken, projectID: UUID? = nil) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(source: source, kind: kind, projectID: projectID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(source: LogSource, projectID: UUID? = nil) {
        for kind in CredentialKind.allCases {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account(source: source, kind: kind, projectID: projectID)
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    static func migrateLegacyCredentials(to projectID: UUID) {
        for source in LogSource.allCases {
            for kind in CredentialKind.allCases {
                guard load(source: source, kind: kind, projectID: projectID) == nil,
                      let value = load(source: source, kind: kind) else { continue }
                try? save(value, source: source, kind: kind, projectID: projectID)
            }
        }
    }

    private static func account(source: LogSource, kind: CredentialKind, projectID: UUID?) -> String {
        if let projectID {
            return "\(projectID.uuidString.lowercased()).\(source.rawValue).\(kind.rawValue)"
        }
        return "\(source.rawValue).\(kind.rawValue)"
    }
}

enum SecretRedactor {
    private static let patterns: [(String, String)] = [
        (#"(?i)\b(bearer\s+)[A-Za-z0-9._~+\-/]+=*"#, "$1<redacted>"),
        (#"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]+\b"#, "stripe_<redacted>"),
        (#"\bsb_(?:secret|publishable)_[A-Za-z0-9._-]+\b"#, "sb_<redacted>"),
        (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "<jwt>"),
        (#"(?i)(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*[^\s,;]+"#, "$1=<redacted>"),
        (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "<email>"),
        (#"\b(?:\d[ -]*?){13,19}\b"#, "<payment-card>"),
        (#"(?i)(cookie|set-cookie)\s*[:=]\s*[^\r\n]+"#, "$1=<redacted>")
    ]

    static func redact(_ value: String) -> String {
        patterns.reduce(value) { partial, rule in
            partial.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }
    }

    static func redact(_ values: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { key, value in
            let sensitiveKey = key.range(of: #"(?i)password|secret|token|authorization|cookie|api.?key"#, options: .regularExpression) != nil
            return (key, sensitiveKey ? "<redacted>" : redact(value))
        })
    }
}

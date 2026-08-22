import Foundation

struct MacReleaseInfo: Codable, Equatable {
    let channel: String?
    let version: String?
    let build: String?
    let downloadURL: URL?
    let notesURL: URL?
    let configured: Bool?

    enum CodingKeys: String, CodingKey {
        case channel
        case version
        case build
        case downloadURL = "downloadUrl"
        case notesURL = "notesUrl"
        case configured
    }
}

/// Pure helpers for deciding whether the hosted release manifest describes a
/// newer app than the one currently running. Unit tested; keep side-effect free.
enum UpdateCheck {
    /// True when the manifest is configured and describes a release newer than
    /// the running app. A missing or identical version never prompts.
    static func isNewer(
        latest: MacReleaseInfo,
        currentVersion: String,
        currentBuild: String?
    ) -> Bool {
        guard let latestVersion = normalized(latest.version), !latestVersion.isEmpty else { return false }
        let current = normalized(currentVersion) ?? "0"
        switch compareVersions(latestVersion, current) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame:
            // Same marketing version: fall back to the build number.
            guard let latestBuildValue = Int((latest.build ?? "").trimmingCharacters(in: .whitespaces)),
                  let currentBuildValue = Int((currentBuild ?? "").trimmingCharacters(in: .whitespaces)) else {
                return false
            }
            return latestBuildValue > currentBuildValue
        }
    }

    /// Compares dot-separated versions numerically ("0.2.10" > "0.2.9"),
    /// ignoring any leading "v" and prerelease suffixes ("-beta.1").
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftComponents = numericComponents(lhs)
        let rightComponents = numericComponents(rhs)
        let longest = max(leftComponents.count, rightComponents.count)
        for index in 0..<longest {
            let left = index < leftComponents.count ? leftComponents[index] : 0
            let right = index < rightComponents.count ? rightComponents[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func normalized(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !text.isEmpty else { return nil }
        if text.hasPrefix("v") { text.removeFirst() }
        if let dashIndex = text.firstIndex(of: "-") {
            text = String(text[..<dashIndex])
        }
        return text.isEmpty ? nil : text
    }

    private static func numericComponents(_ value: String) -> [Int] {
        normalized(value)?
            .split(separator: ".")
            .map { component in
                let digits = component.prefix(while: \.isNumber)
                return Int(digits) ?? 0
            }
            ?? []
    }
}

import Foundation

public struct FeedbackCategory: Codable, Equatable {
    public var topic: String
    public var tat: String
    public var area: String
    public var classification: String
    public var reason: String

    public init(topic: String, tat: String, area: String, classification: String, reason: String) {
        self.topic = topic
        self.tat = tat
        self.area = area
        self.classification = classification
        self.reason = reason
    }
}

public struct FeedbackCategoryInferer {
    public static let defaultBundleMappingPath = "/System/Library/CoreServices/Applications/Feedback Assistant.app/Contents/Resources/bundle-mapping.json"

    private struct Rule {
        var topic: String
        var tat: String
        var area: String
        var keywords: [String]
    }

    private let bundleMappingPath: String
    private let rules: [Rule]

    public init(bundleMappingPath: String = Self.defaultBundleMappingPath) {
        self.bundleMappingPath = bundleMappingPath
        self.rules = [
            Rule(topic: "Developer Technologies & SDKs", tat: "dev.tech", area: "Foundation Models Framework", keywords: ["foundation models", "foundationmodels", "language model", "generable", "tool calling"]),
            Rule(topic: "Developer Tools & Resources", tat: "developertools.fba", area: "Xcode", keywords: ["xcode", "testflight", "app store connect", "simulator", "xctest", "swift compiler", "developer tools"]),
            Rule(topic: "Developer Technologies & SDKs", tat: "dev.tech", area: "APIs and Frameworks", keywords: ["swiftui", "uikit", "appkit", "foundation", "framework", "api", "sdk", "swiftdata"]),
            Rule(topic: "macOS", tat: "public.macos", area: "Something else not on this list", keywords: ["macos", "finder", "safari", "mail", "notes", "desktop", "system settings"]),
            Rule(topic: "iOS & iPadOS", tat: "public.ios", area: "Something else not on this list", keywords: ["ios", "ipados", "iphone", "ipad", "uikit"]),
            Rule(topic: "watchOS", tat: "watchos.public", area: "Something else not on this list", keywords: ["watchos", "apple watch", "watch"]),
            Rule(topic: "tvOS", tat: "tvos.public", area: "Something else not on this list", keywords: ["tvos", "apple tv"]),
            Rule(topic: "visionOS", tat: "public.visionOS", area: "Something else not on this list", keywords: ["visionos", "vision pro", "visionpro"]),
            Rule(topic: "Feedback Assistant", tat: "developertools.fba", area: "Feedback Assistant", keywords: ["feedback assistant", "feedbackassistant", "fb"])
        ]
    }

    public func infer(title: String, description: String = "", bundleID: String? = nil) -> FeedbackCategory {
        let haystack = "\(title)\n\(description)".lowercased()
        let mapping = loadBundleMapping()

        if let bundleID, let mapped = mapping[bundleID] {
            if mapped == "seedx:xcode" {
                return FeedbackCategory(
                    topic: "Developer Tools & Resources",
                    tat: "developertools.fba",
                    area: "Xcode",
                    classification: mapped,
                    reason: "bundle mapping \(bundleID) -> \(mapped)"
                )
            }

            if mapped.hasPrefix("seedx:") {
                return FeedbackCategory(
                    topic: "macOS",
                    tat: "public.macos",
                    area: String(mapped.dropFirst("seedx:".count)),
                    classification: mapped,
                    reason: "bundle mapping \(bundleID) -> \(mapped)"
                )
            }
        }

        var bestRule: Rule?
        var bestScore = 0
        for rule in rules {
            let score = rule.keywords.reduce(0) { count, keyword in
                haystack.contains(keyword) ? count + 1 : count
            }
            if score > bestScore {
                bestScore = score
                bestRule = rule
            }
        }

        if let bestRule {
            return FeedbackCategory(
                topic: bestRule.topic,
                tat: bestRule.tat,
                area: bestRule.area,
                classification: classification(for: bestRule),
                reason: "matched \(bestScore) keyword(s)"
            )
        }

        return FeedbackCategory(
            topic: "macOS",
            tat: "public.macos",
            area: "Something else not on this list",
            classification: "public.macos",
            reason: "fallback"
        )
    }

    private func loadBundleMapping() -> [String: String] {
        guard
            let data = FileManager.default.contents(atPath: bundleMappingPath),
            let mapping = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return mapping
    }

    private func classification(for rule: Rule) -> String {
        if rule.topic == "Developer Tools & Resources" {
            return "seedx:xcode"
        }

        if rule.area == "Foundation Models Framework" {
            return "seed:foundationmodelsframework"
        }

        return rule.tat
    }
}

import Foundation

public enum FeedbackAssistantApp {
    public static func open(_ url: URL) throws {
        try run("/usr/bin/open", arguments: ["-b", FeedbackRoutes.appBundleIdentifier, url.absoluteString])
    }

    public static func fill(payload: PreparedFeedback, scriptURL: URL, selectPopups: Bool = false) throws {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw RelatoError.missingFile(scriptURL.path)
        }
        try run(
            "/usr/bin/osascript",
            arguments: [
                scriptURL.path,
                payload.title,
                payload.description,
                payload.category.area,
                payload.kind.nativeLabel,
                payload.snapshot ?? "",
                payload.bundleID ?? "",
                selectPopups ? "true" : "false"
            ]
        )
    }

    private static func run(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RelatoError.processFailed((launchPath as NSString).lastPathComponent, process.terminationStatus)
        }
    }
}

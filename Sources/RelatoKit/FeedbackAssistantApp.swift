import Foundation

public enum FeedbackAssistantApp {
    public static func open(_ url: URL) throws {
        try run("/usr/bin/open", arguments: ["-b", FeedbackRoutes.appBundleIdentifier, url.absoluteString])
    }

    public static func fill(
        payload: PreparedFeedback,
        selectPopups: Bool = false,
        confirmSubmit: Bool = false
    ) throws {
        try FeedbackAssistantAXDriver().fill(payload: payload, selectPopups: selectPopups, confirmSubmit: confirmSubmit)
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

import Foundation
import RelatoNativeAutomation

public enum FeedbackAssistantApp {
    public static func open(_ url: URL) throws {
        try run("/usr/bin/open", arguments: ["-g", "-b", FeedbackRoutes.appBundleIdentifier, url.absoluteString])
    }

    public static func fill(
        payload: PreparedFeedback,
        selectPopups: Bool = false,
        confirmSubmit: Bool = false
    ) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = RelatoFeedbackAssistantFill(
            payload.title,
            payload.description,
            payload.category.topic,
            payload.category.area,
            payload.kind.nativeLabel,
            payload.snapshot ?? "",
            payload.bundleID ?? "",
            selectPopups,
            confirmSubmit,
            &errorMessage
        )
        defer {
            if let errorMessage {
                RelatoFeedbackAssistantFree(errorMessage)
            }
        }
        guard status == 0 else {
            throw RelatoError.invalidArgument(errorMessage.map { String(cString: $0) } ?? "Feedback Assistant automation failed")
        }
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

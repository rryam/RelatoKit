import Foundation
import RelatoNativeAutomation

public enum FeedbackAssistantApp {
    public struct FillResult: Equatable {
        public var stagedAttachment: DraftAttachment?
    }

    public static func open(_ url: URL) throws {
        try run("/usr/bin/open", arguments: ["-g", "-b", FeedbackRoutes.appBundleIdentifier, url.absoluteString])
    }

    @discardableResult
    public static func fill(
        payload: PreparedFeedback,
        selectPopups: Bool = false,
        confirmSubmit: Bool = false,
        attachmentDraftID: String? = nil,
        storePath: String = FeedbackStore.defaultPath
    ) throws -> FillResult {
        let shouldStageAttachment = payload.snapshot?.isEmpty == false && !allowsForegroundFallback
        if shouldStageAttachment && confirmSubmit {
            try runNativeFill(payload: payload, snapshot: "", selectPopups: selectPopups, confirmSubmit: false)
            let attachment = try FeedbackDraftAttachmentStager.stage(
                snapshotPath: payload.snapshot!,
                draftID: attachmentDraftID,
                storePath: storePath
            )
            try runNativeFill(payload: payload, snapshot: "", selectPopups: selectPopups, confirmSubmit: true)
            return FillResult(stagedAttachment: attachment)
        }

        let nativeSnapshot = shouldStageAttachment ? "" : (payload.snapshot ?? "")
        try runNativeFill(payload: payload, snapshot: nativeSnapshot, selectPopups: selectPopups, confirmSubmit: confirmSubmit)
        let attachment = try shouldStageAttachment ? FeedbackDraftAttachmentStager.stage(
            snapshotPath: payload.snapshot!,
            draftID: attachmentDraftID,
            storePath: storePath
        ) : nil
        return FillResult(stagedAttachment: attachment)
    }

    private static var allowsForegroundFallback: Bool {
        ProcessInfo.processInfo.environment["RELATO_ALLOW_FOREGROUND_FALLBACK"] == "1"
            && ProcessInfo.processInfo.environment["RELATO_DISABLE_FOREGROUND_FALLBACK"] != "1"
    }

    private static func runNativeFill(
        payload: PreparedFeedback,
        snapshot: String,
        selectPopups: Bool,
        confirmSubmit: Bool
    ) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = RelatoFeedbackAssistantFill(
            payload.title,
            payload.description,
            payload.category.topic,
            payload.category.area,
            payload.kind.nativeLabel,
            snapshot,
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

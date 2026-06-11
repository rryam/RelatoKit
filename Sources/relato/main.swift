import Foundation
import RelatoKit

enum RelatoCLI {
    static let version = "0.1.0-dev"

    static func run(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        if arguments == ["--version"] || arguments == ["-v"] {
            print(version)
            return
        }
        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            printHelp()
            return
        }

        let command = arguments.removeFirst()
        switch command {
        case "version":
            print(version)
        case "store":
            try runStore(arguments)
        case "categories":
            try runCategories(arguments)
        case "categorize":
            try runCategorize(arguments)
        case "prepare":
            try runPrepare(arguments)
        case "routes":
            runRoutes()
        case "open":
            try runOpen(arguments)
        case "open-native":
            try runOpenNative(arguments)
        case "fill":
            try runFill(arguments)
        case "submit":
            try runSubmit(arguments)
        default:
            throw RelatoError.invalidArgument("Unknown command: \(command)")
        }
    }

    static func runStore(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("store requires a subcommand: summary, list, uploads")
        }
        let subcommand = arguments.removeFirst()
        let dbPath = try takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        let store = FeedbackStore(path: dbPath)

        switch subcommand {
        case "summary":
            try ensureNoArguments(arguments)
            let rows = try store.summary()
            print("store: \(NSString(string: dbPath).expandingTildeInPath)")
            printTable([["table", "rows"]] + rows.map { [$0.table, String($0.rows)] })
        case "list":
            let limit = try parseLimit(try takeOption("--limit", from: &arguments) ?? "20")
            try ensureNoArguments(arguments)
            let rows = try store.contentItems(limit: limit)
            printTable([["pk", "remote_id", "type", "updated", "title", "subtitle"]] + rows.map { [$0.pk, $0.remoteID, $0.type, $0.updated, $0.title, $0.subtitle] })
        case "uploads":
            let limit = try parseLimit(try takeOption("--limit", from: &arguments) ?? "20")
            try ensureNoArguments(arguments)
            let rows = try store.uploadTasks(limit: limit)
            printTable([["pk", "task_id", "state", "stage", "uploaded", "total"]] + rows.map { [$0.pk, $0.taskID, $0.state, $0.stage, $0.uploaded, $0.total] })
        default:
            throw RelatoError.invalidArgument("Unknown store subcommand: \(subcommand)")
        }
    }

    static func runCategories(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let dbPath = try takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        try ensureNoArguments(arguments)
        let store = FeedbackStore(path: dbPath)
        let rows = try store.formStubs()
        printTable([["topic", "tat", "platform", "description"]] + rows.map { [$0.topic, $0.tat, $0.platform, $0.description] })
    }

    static func runCategorize(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let title = try requireOption("--title", from: &arguments)
        let description = try takeOption("--description", from: &arguments) ?? ""
        let bundleID = try takeOption("--bundle-id", from: &arguments)
        try ensureNoArguments(arguments)
        let category = FeedbackCategoryInferer().infer(title: title, description: description, bundleID: bundleID)
        try printJSON(category)
    }

    static func runPrepare(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let title = try requireOption("--title", from: &arguments)
        let description = try requireOption("--description", from: &arguments)
        let bundleID = try takeOption("--bundle-id", from: &arguments)
        let kindValue = try takeOption("--kind", from: &arguments) ?? "bug"
        guard let kind = FeedbackKind(rawValue: kindValue) else {
            throw RelatoError.invalidArgument("Invalid value for --kind: \(kindValue). Expected bug or suggestion.")
        }
        let outputDir = expandedPath(try takeOption("--output-dir", from: &arguments) ?? FileManager.default.currentDirectoryPath)

        var snapshot = try takeOption("--snapshot", from: &arguments).map(expandedPath)
        try ensureNoArguments(arguments)
        if let snapshotPath = snapshot {
            snapshot = URL(fileURLWithPath: snapshotPath).standardizedFileURL.path
            if !FileManager.default.fileExists(atPath: snapshot!) {
                throw RelatoError.missingFile(snapshot!)
            }
        }

        let category = FeedbackCategoryInferer().infer(title: title, description: description, bundleID: bundleID)
        let payload = try PreparedFeedback(title: title, description: description, snapshot: snapshot, bundleID: bundleID, kind: kind, category: category)

        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let jsonURL = URL(fileURLWithPath: outputDir).appendingPathComponent("feedback-submission.json")
        let markdownURL = URL(fileURLWithPath: outputDir).appendingPathComponent("feedback-submission.md")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: jsonURL)
        try (payload.markdown() + "\n").write(to: markdownURL, atomically: true, encoding: .utf8)

        print("Wrote \(jsonURL.path)")
        print("Wrote \(markdownURL.path)")
        print(payload.url)
    }

    static func runRoutes() {
        for name in FeedbackRoutes.known.keys.sorted() {
            let path = FeedbackRoutes.known[name] ?? ""
            print("\(name.padding(toLength: 15, withPad: " ", startingAt: 0)) \(FeedbackRoutes.webBase)\(path)")
        }
    }

    static func runOpen(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("open requires a route")
        }
        let route = arguments.removeFirst()
        let id = try takeOption("--id", from: &arguments)
        let printOnly = takeFlag("--print-only", from: &arguments)
        try ensureNoArguments(arguments)
        let url = try FeedbackRoutes.url(for: route, id: id)
        if printOnly {
            print(url.absoluteString)
        } else {
            try FeedbackAssistantApp.open(url)
        }
    }

    static func runOpenNative(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let url = try feedbackURL(from: payload)
        try FeedbackAssistantApp.open(url)
    }

    static func runFill(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        let scriptPath = try takeOption("--script", from: &arguments).map(expandedPath)
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let scriptURL = try scriptPath.map(URL.init(fileURLWithPath:)) ?? bundledFillScript()
        try FeedbackAssistantApp.fill(payload: payload, scriptURL: scriptURL, selectPopups: selectPopups)
        if selectPopups {
            print("Set fields and selected requested popups. Review any native-only required fields or diagnostics before submitting.")
        } else {
            print("Set text fields. Select native popups if needed: area='\(payload.category.area)', kind='\(payload.kind.rawValue)'")
        }
    }

    static func runSubmit(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        let confirmSubmit = takeFlag("--confirm", from: &arguments)
        let scriptPath = try takeOption("--script", from: &arguments).map(expandedPath)
        let waitSeconds = try parseSeconds(try takeOption("--wait-seconds", from: &arguments) ?? "1.5", flag: "--wait-seconds")
        let verifyStore = takeFlag("--verify-store", from: &arguments) || confirmSubmit
        let verifyWaitSeconds = try parseSeconds(try takeOption("--verify-wait-seconds", from: &arguments) ?? "3.0", flag: "--verify-wait-seconds")
        let dryRun = takeFlag("--dry-run", from: &arguments)
        let dbPath = try takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let url = try feedbackURL(from: payload)

        if dryRun {
            printSubmitPlan(
                payloadPath: payloadPath,
                payload: payload,
                url: url,
                selectPopups: selectPopups,
                confirmSubmit: confirmSubmit,
                verifyStore: verifyStore,
                dbPath: dbPath
            )
            return
        }

        let store = FeedbackStore(path: dbPath)
        let beforeSnapshot = verifyStore ? try? store.verificationSnapshot(title: payload.title) : nil

        try FeedbackAssistantApp.open(url)
        Thread.sleep(forTimeInterval: waitSeconds)

        let scriptURL = try scriptPath.map(URL.init(fileURLWithPath:)) ?? bundledFillScript()
        try FeedbackAssistantApp.fill(
            payload: payload,
            scriptURL: scriptURL,
            selectPopups: selectPopups,
            confirmSubmit: confirmSubmit
        )

        if confirmSubmit {
            print("Submit click requested through the native Feedback Assistant UI.")
        } else {
            print("Opened and filled Feedback Assistant. Review any native-only required fields or diagnostics, then re-run with --confirm to click the native Submit button.")
        }

        if verifyStore {
            Thread.sleep(forTimeInterval: verifyWaitSeconds)
            let afterSnapshot = try? store.verificationSnapshot(title: payload.title)
            printStoreVerification(before: beforeSnapshot, after: afterSnapshot, title: payload.title)
        }
    }

    static func loadPayload(at path: String) throws -> PreparedFeedback {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RelatoError.missingFile(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        do {
            return try JSONDecoder().decode(PreparedFeedback.self, from: data)
        } catch {
            throw RelatoError.invalidArgument("Could not decode payload at \(path): \(friendlyDecodeError(error))")
        }
    }

    static func feedbackURL(from payload: PreparedFeedback) throws -> URL {
        guard
            let components = URLComponents(string: payload.url),
            components.scheme == "https",
            components.host == "feedbackassistant.apple.com",
            let url = components.url
        else {
            throw RelatoError.invalidArgument("Payload URL must be an https://feedbackassistant.apple.com URL")
        }
        return url
    }

    static func bundledFillScript() throws -> URL {
        if let url = Bundle.module.url(forResource: "feedback_native_fill", withExtension: "applescript") {
            return url
        }
        throw RelatoError.missingFile("feedback_native_fill.applescript")
    }

    static func takeOption(_ name: String, from arguments: inout [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        arguments.remove(at: index)
        guard index < arguments.count, !arguments[index].hasPrefix("--") else {
            throw RelatoError.missingValue(name)
        }
        return arguments.remove(at: index)
    }

    static func requireOption(_ name: String, from arguments: inout [String]) throws -> String {
        guard let value = try takeOption(name, from: &arguments), !value.isEmpty else {
            throw RelatoError.missingValue(name)
        }
        return value
    }

    static func takeFlag(_ name: String, from arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: name) else { return false }
        arguments.remove(at: index)
        return true
    }

    static func ensureNoArguments(_ arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw RelatoError.invalidArgument("Unexpected argument(s): \(arguments.joined(separator: " "))")
        }
    }

    static func parseLimit(_ value: String) throws -> Int {
        guard let limit = Int(value), limit >= 0 else {
            throw RelatoError.invalidArgument("Invalid value for --limit: \(value). Expected a non-negative integer.")
        }
        return limit
    }

    static func parseSeconds(_ value: String, flag: String) throws -> Double {
        guard let seconds = Double(value), seconds >= 0 else {
            throw RelatoError.invalidArgument("Invalid value for \(flag): \(value). Expected a non-negative number.")
        }
        return seconds
    }

    static func friendlyDecodeError(_ error: Error) -> String {
        if case let DecodingError.dataCorrupted(context) = error {
            return context.debugDescription
        }
        if case let DecodingError.keyNotFound(key, _) = error {
            return "missing key '\(key.stringValue)'"
        }
        if case let DecodingError.valueNotFound(_, context) = error {
            return "missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        }
        if case let DecodingError.typeMismatch(_, context) = error {
            return "type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        }
        return error.localizedDescription
    }

    static func expandedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    static func printTable(_ rows: [[String]]) {
        guard let first = rows.first else { return }
        let widths = first.indices.map { index in
            rows.map { row in index < row.count ? row[index].count : 0 }.max() ?? 0
        }
        for row in rows {
            let line = row.indices.map { index in
                row[index].padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            print(line)
        }
    }

    static func printStoreVerification(
        before: StoreVerificationSnapshot?,
        after: StoreVerificationSnapshot?,
        title: String
    ) {
        print("")
        print("Local store verification:")

        guard let after else {
            print("  could not read Feedback Assistant store after native handoff")
            return
        }

        if let before {
            let contentDelta = after.contentItemCount - before.contentItemCount
            let uploadDelta = after.uploadTaskCount - before.uploadTaskCount
            print("  content items: \(before.contentItemCount) -> \(after.contentItemCount) (\(signed(contentDelta)))")
            print("  upload tasks:   \(before.uploadTaskCount) -> \(after.uploadTaskCount) (\(signed(uploadDelta)))")
        } else {
            print("  content items: \(after.contentItemCount)")
            print("  upload tasks:   \(after.uploadTaskCount)")
        }

        if !after.matchingItems.isEmpty {
            print("  matching local item(s) for title '\(title)':")
            for item in after.matchingItems {
                let displayTitle = item.title.isEmpty ? item.subtitle : item.title
                print("    #\(item.pk) remote_id=\(item.remoteID) type=\(item.type) updated=\(item.updated) \(displayTitle)")
            }
        } else if let newest = after.newestItem {
            let displayTitle = newest.title.isEmpty ? newest.subtitle : newest.title
            print("  no exact title match found; newest local item is #\(newest.pk) \(displayTitle)")
        } else {
            print("  no local content items found")
        }

        print("  note: this is a best-effort local check, not an Apple server receipt")
    }

    static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    static func printSubmitPlan(
        payloadPath: String,
        payload: PreparedFeedback,
        url: URL,
        selectPopups: Bool,
        confirmSubmit: Bool,
        verifyStore: Bool,
        dbPath: String
    ) {
        print("Submit plan:")
        print("  payload:       \(payloadPath)")
        print("  title:         \(payload.title)")
        print("  topic:         \(payload.category.topic)")
        print("  area:          \(payload.category.area)")
        print("  kind:          \(payload.kind.rawValue)")
        print("  bundle ID:     \(payload.bundleID ?? "")")
        print("  snapshot:      \(payload.snapshot ?? "")")
        print("  native URL:    \(url.absoluteString)")
        print("  select popups: \(selectPopups ? "yes" : "no")")
        print("  click Submit:  \(confirmSubmit ? "yes (--confirm)" : "no")")
        print("  verify store:  \(verifyStore ? "yes" : "no")")
        if verifyStore {
            print("  store:         \(NSString(string: dbPath).expandingTildeInPath)")
        }
    }

    static func printHelp() {
        print(
            """
            relato: local-first tooling for Feedback Assistant workflows

            Commands:
              relato version
              relato store summary [--db PATH]
              relato store list [--limit N] [--db PATH]
              relato store uploads [--limit N] [--db PATH]
              relato categories [--db PATH]
              relato categorize --title TEXT [--description TEXT] [--bundle-id ID]
              relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]
              relato routes
              relato open ROUTE [--id ID] [--print-only]
              relato open-native [--payload PATH]
              relato fill [--payload PATH] [--select-popups] [--script PATH]
              relato submit [--payload PATH] [--select-popups] [--script PATH] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]
            """
        )
    }
}

do {
    try RelatoCLI.run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    Foundation.exit(1)
}

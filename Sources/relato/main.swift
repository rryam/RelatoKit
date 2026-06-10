import Foundation
import RelatoKit

enum RelatoCLI {
    static func run(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            printHelp()
            return
        }

        let command = arguments.removeFirst()
        switch command {
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
        let dbPath = takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        let store = FeedbackStore(path: dbPath)

        switch subcommand {
        case "summary":
            print("store: \(NSString(string: dbPath).expandingTildeInPath)")
            printTable([["table", "rows"]] + (try store.summary()).map { [$0.table, String($0.rows)] })
        case "list":
            let limit = Int(takeOption("--limit", from: &arguments) ?? "20") ?? 20
            let rows = try store.contentItems(limit: limit)
            printTable([["pk", "remote_id", "type", "updated", "title", "subtitle"]] + rows.map { [$0.pk, $0.remoteID, $0.type, $0.updated, $0.title, $0.subtitle] })
        case "uploads":
            let limit = Int(takeOption("--limit", from: &arguments) ?? "20") ?? 20
            let rows = try store.uploadTasks(limit: limit)
            printTable([["pk", "task_id", "state", "stage", "uploaded", "total"]] + rows.map { [$0.pk, $0.taskID, $0.state, $0.stage, $0.uploaded, $0.total] })
        default:
            throw RelatoError.invalidArgument("Unknown store subcommand: \(subcommand)")
        }
    }

    static func runCategories(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let dbPath = takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        let store = FeedbackStore(path: dbPath)
        let rows = try store.formStubs()
        printTable([["topic", "tat", "platform", "description"]] + rows.map { [$0.topic, $0.tat, $0.platform, $0.description] })
    }

    static func runCategorize(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let title = try requireOption("--title", from: &arguments)
        let description = takeOption("--description", from: &arguments) ?? ""
        let bundleID = takeOption("--bundle-id", from: &arguments)
        let category = FeedbackCategoryInferer().infer(title: title, description: description, bundleID: bundleID)
        try printJSON(category)
    }

    static func runPrepare(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let title = try requireOption("--title", from: &arguments)
        let description = try requireOption("--description", from: &arguments)
        let bundleID = takeOption("--bundle-id", from: &arguments)
        let kind = FeedbackKind(rawValue: takeOption("--kind", from: &arguments) ?? "bug") ?? .bug
        let outputDir = expandedPath(takeOption("--output-dir", from: &arguments) ?? FileManager.default.currentDirectoryPath)

        var snapshot = takeOption("--snapshot", from: &arguments).map(expandedPath)
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
        let id = takeOption("--id", from: &arguments)
        let printOnly = takeFlag("--print-only", from: &arguments)
        let url = try FeedbackRoutes.url(for: route, id: id)
        if printOnly {
            print(url.absoluteString)
        } else {
            try FeedbackAssistantApp.open(url)
        }
    }

    static func runOpenNative(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let payload = try loadPayload(at: payloadPath)
        guard let url = URL(string: payload.url) else {
            throw RelatoError.invalidArgument("Payload URL is invalid")
        }
        try FeedbackAssistantApp.open(url)
    }

    static func runFill(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        let scriptPath = takeOption("--script", from: &arguments).map(expandedPath)
        let payload = try loadPayload(at: payloadPath)
        let scriptURL = try scriptPath.map(URL.init(fileURLWithPath:)) ?? bundledFillScript()
        try FeedbackAssistantApp.fill(payload: payload, scriptURL: scriptURL, selectPopups: selectPopups)
        if !selectPopups {
            print("Set text fields. Select native popups if needed: area='\(payload.category.area)', kind='\(payload.kind.rawValue)'")
        }
    }

    static func runSubmit(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        let confirmSubmit = takeFlag("--confirm", from: &arguments)
        let scriptPath = takeOption("--script", from: &arguments).map(expandedPath)
        let waitSeconds = Double(takeOption("--wait-seconds", from: &arguments) ?? "1.5") ?? 1.5
        let verifyStore = takeFlag("--verify-store", from: &arguments) || confirmSubmit
        let verifyWaitSeconds = Double(takeOption("--verify-wait-seconds", from: &arguments) ?? "3.0") ?? 3.0
        let dbPath = takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        let payload = try loadPayload(at: payloadPath)
        guard let url = URL(string: payload.url) else {
            throw RelatoError.invalidArgument("Payload URL is invalid")
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
            print("Opened and filled Feedback Assistant. Re-run with --confirm to click the native Submit button.")
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
        return try JSONDecoder().decode(PreparedFeedback.self, from: data)
    }

    static func bundledFillScript() throws -> URL {
        if let url = Bundle.module.url(forResource: "feedback_native_fill", withExtension: "applescript") {
            return url
        }
        throw RelatoError.missingFile("feedback_native_fill.applescript")
    }

    static func takeOption(_ name: String, from arguments: inout [String]) -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        arguments.remove(at: index)
        guard index < arguments.count else { return nil }
        return arguments.remove(at: index)
    }

    static func requireOption(_ name: String, from arguments: inout [String]) throws -> String {
        guard let value = takeOption(name, from: &arguments), !value.isEmpty else {
            throw RelatoError.missingValue(name)
        }
        return value
    }

    static func takeFlag(_ name: String, from arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: name) else { return false }
        arguments.remove(at: index)
        return true
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

    static func printHelp() {
        print(
            """
            relato: local-first tooling for Feedback Assistant workflows

            Commands:
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
              relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--confirm] [--verify-store]
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

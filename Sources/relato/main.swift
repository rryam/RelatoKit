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

        if arguments.isEmpty {
            printHelp()
            return
        }
        if arguments == ["--help"] || arguments == ["-h"] {
            printHelp()
            return
        }

        let command = arguments.removeFirst()
        if command == "help" {
            try printHelpTopic(arguments)
            return
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            printHelp(topic: command)
            return
        }

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
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let fillResult = try FeedbackAssistantApp.fill(payload: payload, selectPopups: selectPopups)
        if selectPopups {
            print("Set fields and selected requested popups through Accessibility. Review native-only fields and remember local verification is not an Apple server receipt.")
        } else {
            print("Set fields through Accessibility. Select native popups if needed: area='\(payload.category.area)', kind='\(payload.kind.rawValue)'")
        }
        printStagedAttachment(fillResult.stagedAttachment)
    }

    static func runSubmit(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        let confirmSubmit = takeFlag("--confirm", from: &arguments)
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

        let fillResult = try FeedbackAssistantApp.fill(
            payload: payload,
            selectPopups: selectPopups,
            confirmSubmit: confirmSubmit,
            storePath: dbPath
        )

        if confirmSubmit {
            print("Submit press requested through the native Feedback Assistant UI.")
        } else {
            print("Opened, filled, and hid Feedback Assistant through Accessibility. Review any native-only fields or diagnostics, then re-run with --confirm to press the native Submit button.")
        }
        printStagedAttachment(fillResult.stagedAttachment)

        if verifyStore {
            Thread.sleep(forTimeInterval: verifyWaitSeconds)
            let afterSnapshot = try? store.verificationSnapshot(title: payload.title)
            printStoreVerification(before: beforeSnapshot, after: afterSnapshot, title: payload.title)
        }
    }

    static func printStagedAttachment(_ attachment: DraftAttachment?) {
        guard let attachment else { return }
        print("Staged snapshot in Feedback Assistant draft \(attachment.draftID): \(attachment.path)")
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

    static func printHelpTopic(_ arguments: [String]) throws {
        if arguments.isEmpty {
            printHelp()
            return
        }
        guard arguments.count == 1 else {
            throw RelatoError.invalidArgument("help accepts at most one topic")
        }
        printHelp(topic: arguments[0])
    }

    static func printHelp(topic: String) {
        switch topic {
        case "payload", "prepare":
            printPrepareHelp()
        case "submit":
            printSubmitHelp()
        case "fill":
            printFillHelp()
        case "store":
            printStoreHelp()
        default:
            printHelp()
        }
    }

    static func printHelp() {
        print(
            """
            relato: agent-first tooling for Apple Feedback Assistant workflows

            RelatoKit is designed for coding agents preparing useful Feedback Assistant
            reports through Apple's native macOS app. It keeps authentication, diagnostics,
            and final submission inside Feedback Assistant.

            Agent workflow:
              1. Research the issue and write any supporting evidence to a local file.
              2. Run `relato prepare` to create the payload pair:
                   feedback-submission.json  machine-readable contract for relato
                   feedback-submission.md    human-readable report for review/logs
              3. Inspect the Markdown and JSON before touching the native app.
              4. Run `relato submit --dry-run --payload feedback-submission.json`.
              5. Run `relato submit --payload feedback-submission.json` to open/fill only.
              6. Inspect Feedback Assistant for native-only fields, diagnostics, and files.
              7. Only after explicit user confirmation, run with `--confirm`.
              8. Use `relato store list` and `relato store uploads` as local evidence.

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
              relato fill [--payload PATH] [--select-popups]
              relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

            Help topics:
              relato help payload
              relato help prepare
              relato help submit
              relato help fill
              relato help store

            Safety:
              `--confirm` presses the native Submit button through Accessibility. It is not headless
              submission and local store verification is not an Apple server receipt.
              Native form automation uses an Objective-C Accessibility engine with passive
              AX value writes for fields; it does not synthesize mouse or keyboard input.
              Feedback Assistant is opened without activation and hidden after launch/fill.
              Snapshot attachments are staged into the local Feedback Assistant draft
              folder in the background after the native draft exists.
              Cua/Peekaboo-style background input was tested: hidden text fields work,
              Feedback Assistant SwiftUI popups still fail closed.
            """
        )
    }

    static func printPrepareHelp() {
        print(
            """
            relato prepare: create the payload pair agents should review and reuse

            Usage:
              relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]

            Outputs:
              feedback-submission.json
                Machine-readable payload consumed by `open-native`, `fill`, and `submit`.
                Keep this file as the source of truth for the native handoff.

              feedback-submission.md
                Human-readable review artifact. Use it in agent logs, PR notes, or as an
                attachment when useful.

            Options:
              --title TEXT          Feedback title.
              --description TEXT    Full report body. Preserve real newlines.
              --snapshot PATH       Local evidence attachment. This can be a screenshot,
                                    Markdown note, log, sysdiagnose pointer, or sample file.
              --bundle-id ID        App bundle ID when relevant.
              --kind VALUE          bug or suggestion. Defaults to bug.
              --output-dir DIR      Where to write the JSON and Markdown files.

            Agent pattern:
              relato prepare \\
                --title "Foundation Models framework: add first-class video input support" \\
                --description "$REPORT_BODY" \\
                --snapshot ./evidence.md \\
                --kind suggestion \\
                --output-dir /tmp/relato-report

              sed -n '1,220p' /tmp/relato-report/feedback-submission.md
              relato submit --payload /tmp/relato-report/feedback-submission.json --dry-run
            """
        )
    }

    static func printSubmitHelp() {
        print(
            """
            relato submit: open/fill Feedback Assistant and optionally click native Submit

            Usage:
              relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

            Default behavior:
              Without `--confirm`, this opens Feedback Assistant without activation, fills
              the native form from the JSON payload, hides the app, and stops before Submit.

            Confirmation:
              --confirm             Presses the native Submit button through
                                    Accessibility automation. Use only after explicit
                                    user confirmation at action time.

            Verification:
              --verify-store        Reads the local Feedback Assistant store before/after
                                    the handoff and prints local deltas.
              --db PATH             Override the local Feedback Assistant SQLite path.
              --dry-run             Print the planned native handoff without opening,
                                    filling, attaching, or submitting.

            Native form reality:
              Apple can add topic-specific required fields, popups, diagnostics, or log
              gathering. Agents should inspect the native app before `--confirm`; the
              local store check is useful evidence but not a server-side receipt.
              RelatoKit uses an Objective-C Accessibility engine for native UI automation.
              Text fields are set through passive AX value writes, without moving focus,
              clicking, or synthesizing keyboard input.
              Snapshot attachments are staged into the local Feedback Assistant draft folder after the native draft
              exists, avoiding the Add Attachment picker. RelatoKit fails closed instead of
              foregrounding Feedback Assistant when a native control refuses background automation.
              Feedback Assistant's SwiftUI popups can expose no selectable AX children while
              hidden; in that case `--select-popups` fails closed instead of taking over input.
              Cua/Peekaboo-style background input was tested and kept as a boundary:
              useful for hidden text-field validation, not reliable for these popups.

            Agent pattern:
              relato submit --payload feedback-submission.json --dry-run --confirm
              relato submit --payload feedback-submission.json
              # inspect native UI and satisfy Apple-only fields
              relato submit --payload feedback-submission.json --confirm --verify-store
              relato store list --limit 10
              relato store uploads --limit 10
            """
        )
    }

    static func printFillHelp() {
        print(
            """
            relato fill: fill the currently open Feedback Assistant draft

            Usage:
              relato fill [--payload PATH] [--select-popups]

            Notes:
              This does not open a new route and does not submit. It is useful when an
              agent has already navigated the native app, manually selected a topic, or
              needs to retry form fill after changing native-only fields.

              --select-popups asks the AX driver to select known area/type popups. Feedback
              Assistant SwiftUI popups may expose no selectable AX children while hidden;
              when that happens RelatoKit fails closed instead of stealing input.
            """
        )
    }

    static func printStoreHelp() {
        print(
            """
            relato store: inspect the local Feedback Assistant store

            Usage:
              relato store summary [--db PATH]
              relato store list [--limit N] [--db PATH]
              relato store uploads [--limit N] [--db PATH]

            Agent pattern:
              relato store summary
              relato store list --limit 10
              relato store uploads --limit 10

            Notes:
              Store reads are local evidence only. They can show drafts, recent items,
              and upload tasks, but they are not Apple server receipts.
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

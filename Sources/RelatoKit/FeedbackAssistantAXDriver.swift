import AppKit
import ApplicationServices
import Foundation

public struct FeedbackAssistantAXDriver {
    private let bundleIdentifier: String
    private let pollInterval: TimeInterval

    public init(
        bundleIdentifier: String = FeedbackRoutes.appBundleIdentifier,
        pollInterval: TimeInterval = 0.25
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.pollInterval = pollInterval
    }

    public func fill(
        payload: PreparedFeedback,
        selectPopups: Bool = false,
        confirmSubmit: Bool = false
    ) throws {
        guard AXIsProcessTrusted() else {
            throw RelatoError.invalidArgument("Accessibility permission is required for AX form filling")
        }

        let app = try appElement()

        if let window = try waitForWindow(named: "Choose Topic", in: app, timeout: 8) {
            try chooseTopic(payload.category.topic, in: window)
            try pressButton(named: "Continue", in: window)
        }

        let formWindow = try waitForElement(
            in: app,
            timeout: 12,
            matching: { node in
                node.isTextInput && node.matches("Please provide a descriptive title for your feedback:")
            }
        )

        guard let window = try containingWindow(for: formWindow, in: app) ?? firstWindow(in: app) else {
            throw RelatoError.invalidArgument("Could not find Feedback Assistant form window")
        }

        try setTextInput(
            matching: "Please provide a descriptive title for your feedback:",
            to: payload.title,
            in: window
        )
        try setTextInput(
            matching: "Please describe the issue and what steps we can take to reproduce it",
            to: payload.description,
            in: window
        )

        if let bundleID = payload.bundleID, !bundleID.isEmpty {
            try? setTextInput(
                matching: "Please provide the bundleId or appAppleId of your app:",
                to: bundleID,
                in: window
            )
        }

        if selectPopups {
            try selectPopup(matching: "Which area are you seeing an issue with?", value: payload.category.area, in: window)
            try selectPopup(matching: "What type of feedback are you reporting?", value: payload.kind.nativeLabel, in: window)
        }

        if let snapshot = payload.snapshot, !snapshot.isEmpty {
            try attachFile(at: snapshot, in: window)
        }

        if confirmSubmit {
            try pressSubmit(in: window)
        }
    }

    private func appElement() throws -> AXUIElement {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            throw RelatoError.invalidArgument("Feedback Assistant is not running")
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func waitForWindow(named title: String, in app: AXUIElement, timeout: TimeInterval) throws -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let window = try windows(in: app).first(where: { node($0).matches(title) }) {
                return window
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        return nil
    }

    private func waitForElement(
        in app: AXUIElement,
        timeout: TimeInterval,
        matching predicate: (AXNode) -> Bool
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = descendants(of: app, maxDepth: 10).first(where: { predicate(node($0)) }) {
                return element
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        throw RelatoError.invalidArgument("Timed out waiting for Feedback Assistant form")
    }

    private func firstWindow(in app: AXUIElement) throws -> AXUIElement? {
        try windows(in: app).first
    }

    private func windows(in app: AXUIElement) throws -> [AXUIElement] {
        try elements(attribute: kAXWindowsAttribute, from: app)
    }

    private func containingWindow(for element: AXUIElement, in app: AXUIElement) throws -> AXUIElement? {
        let targetID = CFHash(element)
        return try windows(in: app).first { window in
            descendants(of: window, maxDepth: 10).contains { CFHash($0) == targetID }
        }
    }

    private func chooseTopic(_ topic: String, in window: AXUIElement) throws {
        guard let row = descendants(of: window, maxDepth: 10).first(where: { element in
            node(element).role == "AXRow" && descendants(of: element, maxDepth: 5).contains { node($0).matches(topic) }
        }) else {
            throw RelatoError.invalidArgument("Could not find topic: \(topic)")
        }

        _ = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        try press(row, label: topic)
    }

    private func setTextInput(matching label: String, to value: String, in root: AXUIElement) throws {
        guard let input = descendants(of: root, maxDepth: 10).first(where: { element in
            let candidate = node(element)
            return candidate.isTextInput && candidate.matches(label)
        }) else {
            throw RelatoError.invalidArgument("Could not find text input: \(label)")
        }

        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(input, kAXValueAttribute as CFString, &settable)
        guard settableError == .success, settable.boolValue else {
            throw RelatoError.invalidArgument("Text input is not AX-settable: \(label)")
        }

        let error = AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, value as CFString)
        guard error == .success else {
            throw RelatoError.invalidArgument("Could not set text input \(label): \(error)")
        }
    }

    private func selectPopup(matching label: String, value: String, in root: AXUIElement) throws {
        guard let popup = descendants(of: root, maxDepth: 10).first(where: { element in
            let candidate = node(element)
            return candidate.role == "AXPopUpButton" && candidate.matches(label)
        }) else {
            throw RelatoError.invalidArgument("Could not find popup: \(label)")
        }

        try press(popup, label: label)
        Thread.sleep(forTimeInterval: 0.5)

        let searchRoots = [root, AXUIElementCreateSystemWide()]
        for searchRoot in searchRoots {
            if let item = descendants(of: searchRoot, maxDepth: 12).first(where: { element in
                let candidate = node(element)
                return (candidate.role == "AXMenuItem" || candidate.role == "AXStaticText") && candidate.matches(value)
            }) {
                try press(item, label: value)
                return
            }
        }

        throw RelatoError.invalidArgument("Could not select popup value '\(value)' for \(label)")
    }

    private func attachFile(at path: String, in root: AXUIElement) throws {
        try pressButton(named: "Add Attachment", in: root)
        Thread.sleep(forTimeInterval: 0.8)

        let app = try appElement()
        guard let pickerRoot = try windows(in: app).first(where: { window in
            let candidate = node(window)
            return candidate.matches("Open") || candidate.matches("Choose") || candidate.matches("Attach")
        }) ?? firstWindow(in: app) else {
            throw RelatoError.invalidArgument("Could not find native attachment picker")
        }

        guard let pathInput = descendants(of: pickerRoot, maxDepth: 12).first(where: { element in
            let candidate = node(element)
            return candidate.isTextInput && isSettable(element, attribute: kAXValueAttribute)
        }) else {
            throw RelatoError.invalidArgument("Attachment picker did not expose an AX-settable path field")
        }

        let setError = AXUIElementSetAttributeValue(pathInput, kAXValueAttribute as CFString, path as CFString)
        guard setError == .success else {
            throw RelatoError.invalidArgument("Could not set attachment path through AX: \(setError)")
        }

        if let openButton = findButton(named: "Open", in: pickerRoot) ?? findButton(named: "Choose", in: pickerRoot) {
            try press(openButton, label: "Open")
        } else {
            throw RelatoError.invalidArgument("Could not find attachment picker Open button")
        }
    }

    private func pressSubmit(in root: AXUIElement) throws {
        if let button = findButton(named: "Submit", in: root) {
            try press(button, label: "Submit")
            return
        }
        throw RelatoError.invalidArgument("Could not find Submit button")
    }

    private func pressButton(named name: String, in root: AXUIElement) throws {
        if let button = findButton(named: name, in: root) {
            try press(button, label: name)
            return
        }
        throw RelatoError.invalidArgument("Could not find button: \(name)")
    }

    private func findButton(named name: String, in root: AXUIElement) -> AXUIElement? {
        descendants(of: root, maxDepth: 10).first { element in
            let candidate = node(element)
            return candidate.role == "AXButton" && candidate.matches(name)
        }
    }

    private func press(_ element: AXUIElement, label: String) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            throw RelatoError.invalidArgument("Could not press \(label): \(error)")
        }
    }

    private func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private func descendants(of root: AXUIElement, maxDepth: Int) -> [AXUIElement] {
        guard maxDepth >= 0 else { return [] }

        var result: [AXUIElement] = []
        for child in (try? elements(attribute: kAXChildrenAttribute, from: root)) ?? [] {
            result.append(child)
            result.append(contentsOf: descendants(of: child, maxDepth: maxDepth - 1))
        }
        for child in (try? elements(attribute: kAXRowsAttribute, from: root)) ?? [] {
            result.append(child)
            result.append(contentsOf: descendants(of: child, maxDepth: maxDepth - 1))
        }
        for child in (try? elements(attribute: kAXVisibleChildrenAttribute, from: root)) ?? [] {
            result.append(child)
            result.append(contentsOf: descendants(of: child, maxDepth: maxDepth - 1))
        }
        return result
    }

    private func elements(attribute: String, from element: AXUIElement) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func node(_ element: AXUIElement) -> AXNode {
        AXNode(
            role: stringAttribute(kAXRoleAttribute, from: element),
            title: stringAttribute(kAXTitleAttribute, from: element),
            description: stringAttribute(kAXDescriptionAttribute, from: element),
            value: stringAttribute(kAXValueAttribute, from: element)
        )
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        if let string = value as? String {
            return string
        }
        guard let value else { return "" }
        return String(describing: value)
    }
}

private struct AXNode {
    var role: String
    var title: String
    var description: String
    var value: String

    var isTextInput: Bool {
        role == "AXTextField" || role == "AXTextArea"
    }

    func matches(_ text: String) -> Bool {
        [title, description, value].contains { candidate in
            candidate == text || candidate.hasPrefix(text) || candidate.localizedCaseInsensitiveContains(text)
        }
    }
}

import Foundation
import Testing
@testable import RelatoKit

@Test func preparedFeedbackBuildsFeedbackAssistantURL() throws {
    let category = FeedbackCategory(
        topic: "Developer Tools & Resources",
        tat: "developertools.fba",
        area: "Xcode",
        classification: "seedx:xcode",
        reason: "test"
    )

    let payload = try PreparedFeedback(
        title: "Canvas fails after rename",
        description: "Steps, expected result, actual result.",
        snapshot: "/tmp/snapshot.png",
        bundleID: "com.apple.dt.Xcode",
        kind: .bug,
        category: category
    )

    let components = try #require(URLComponents(string: payload.url))
    #expect(components.scheme == "https")
    #expect(components.host == "feedbackassistant.apple.com")
    #expect(components.path == "/new")

    let queryItems = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )
    #expect(queryItems["title"] == "Canvas fails after rename")
    #expect(queryItems["description"] == "Steps, expected result, actual result.")
    #expect(queryItems["classification"] == "seedx:xcode")
    #expect(queryItems["area"] == "Xcode")
    #expect(queryItems["path"] == "/tmp/snapshot.png")
}

@Test func routeWithIDReplacesPlaceholder() throws {
    let url = try FeedbackRoutes.url(for: "feedback", id: "123456")
    #expect(url.absoluteString == "https://feedbackassistant.apple.com/feedback/123456")
}

@Test func routeWithMissingIDThrows() {
    #expect(throws: RelatoError.self) {
        try FeedbackRoutes.url(for: "feedback")
    }
}

import Testing
@testable import RelatoKit

@Test func xcodeBundleMapsToDeveloperTools() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "Xcode preview does not update",
        description: "Simulator and XCTest are involved.",
        bundleID: nil
    )

    #expect(category.topic == "Developer Tools & Resources")
    #expect(category.area == "Xcode")
    #expect(category.classification == "seedx:xcode")
}

@Test func fallbackIsMacOS() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(title: "Something weird", description: "No known words here.")

    #expect(category.topic == "macOS")
    #expect(category.classification == "public.macos")
}

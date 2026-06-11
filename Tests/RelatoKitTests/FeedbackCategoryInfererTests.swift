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

@Test func foundationModelsMapsToSpecificFrameworkArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "Foundation Models framework should accept video input",
        description: "LanguageModel and tool calling should support temporal media."
    )

    #expect(category.topic == "Developer Technologies & SDKs")
    #expect(category.tat == "dev.tech")
    #expect(category.area == "Foundation Models Framework")
    #expect(category.classification == "seed:foundationmodelsframework")
}

@Test func appStoreConnectMapsToDeveloperToolsArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "App Store Connect API returns an unexpected relationship error",
        description: "The App Store Connect API response is missing expected build data."
    )

    #expect(category.topic == "Developer Tools & Resources")
    #expect(category.tat == "developertools.fba")
    #expect(category.area == "App Store Connect API")
    #expect(category.classification == "seed:appstoreconnectAPI")
}

@Test func swiftUIMapsToDeveloperTechnologyArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "SwiftUI sheet dismisses immediately",
        description: "A SwiftUI presentation regression occurs on macOS."
    )

    #expect(category.topic == "Developer Technologies & SDKs")
    #expect(category.area == "SwiftUI")
    #expect(category.classification == "seed:swiftui")
}

@Test func safariMapsToMacOSArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "Safari tab groups disappear after relaunch",
        description: "The issue reproduces on macOS."
    )

    #expect(category.topic == "macOS")
    #expect(category.tat == "public.macos")
    #expect(category.area == "Safari")
    #expect(category.classification == "seedx:safari")
}

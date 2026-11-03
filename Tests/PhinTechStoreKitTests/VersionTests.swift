import Foundation
import Testing
@testable import PhinTechStoreKit

@Test func versionMatchesProjectYml() throws {
    // Tests/PhinTechStoreKitTests/VersionTests.swift -> the repository
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
    #expect(project.contains("MARKETING_VERSION: \"\(PhinTechStoreVersion.current)\""),
            "PhinTechStoreVersion.current differs from project.yml; bump with `just bump`, which writes both")
}

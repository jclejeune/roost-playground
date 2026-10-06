import Foundation
import Testing
@testable import PlaygroundCore

/// Installed binaries build previews against `playgroundVersion`, so the README must install that tag.
@Suite("Release consistency")
struct ReleaseTests {
    let readme: String

    init() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        readme = try String(contentsOf: root.appending(path: "README.md"), encoding: .utf8)
    }

    @Test func readmeInstallsTheCurrentVersion() {
        #expect(readme.contains("mint install roost-framework/roost-playground@v\(playgroundVersion)\n"))
    }

    @Test func readmeShowsTheStarterThatNewWrites() {
        #expect(readme.contains("```swift\n\(starterPlayground)```"))
    }
}

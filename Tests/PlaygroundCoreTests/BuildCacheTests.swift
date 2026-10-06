import Foundation
import Testing
@testable import PlaygroundCore

@Suite("Session build cache")
struct BuildCacheTests {
    @Test func retainsImmutableArtifactsAndEvictsLeastRecentlyUsed() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let input = fixture.root.appending(path: "products")
        try FileManager.default.createDirectory(at: input.appending(path: "Theme.bundle"), withIntermediateDirectories: true)
        let executable = input.appending(path: "PlaygroundPage")
        try "version A".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let theme = input.appending(path: "Theme.bundle/style.css")
        try "blue".write(to: theme, atomically: true, encoding: .utf8)
        let cache = try BuildCache(directory: fixture.root.appending(path: "versions"), capacity: 2)
        let a = digest("A"), b = digest("B"), c = digest("C")
        try cache.store(a, from: input)
        try "version B".write(to: executable, atomically: false, encoding: .utf8)
        try "red".write(to: theme, atomically: false, encoding: .utf8)
        let saved = try #require(try cache.lookup(a))
        #expect(try String(contentsOf: saved.appending(path: "PlaygroundPage"), encoding: .utf8) == "version A")
        #expect(try String(contentsOf: saved.appending(path: "Theme.bundle/style.css"), encoding: .utf8) == "blue")
        try cache.store(b, from: input)
        #expect(try cache.lookup(a) != nil)
        try cache.store(c, from: input)
        #expect(try cache.lookup(b) == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.directory.appending(path: b).path))
        #expect(try cache.lookup(a) != nil)
        try FileManager.default.removeItem(at: saved.appending(path: "Theme.bundle"))
        #expect(try cache.lookup(a) == nil)
        #expect(!FileManager.default.fileExists(atPath: saved.path))
        try cache.clear()
        #expect(!FileManager.default.fileExists(atPath: cache.directory.path))
        #expect(FileManager.default.fileExists(atPath: executable.path))
    }

    @Test func newSessionDiscardsLeftoversWithoutTouchingOtherCaches() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let directory = fixture.root.appending(path: "versions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "old binary".write(to: directory.appending(path: "leftover"), atomically: true, encoding: .utf8)
        let other = fixture.root.appending(path: "other-versions")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let cache = try BuildCache(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(try cache.lookup(digest("unknown")) == nil)
    }

    @Test func incompleteProductsAreNeverAdmitted() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let input = fixture.root.appending(path: "incomplete-products")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let cache = try BuildCache(directory: fixture.root.appending(path: "versions"))
        let hash = digest("incomplete")
        #expect(throws: PlaygroundError.self) { try cache.store(hash, from: input) }
        #expect(try cache.lookup(hash) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.directory.path).isEmpty)
    }

    @Test func dependencyContentsAndResourcesInvalidateBuildIdentity() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let package = fixture.configuration.packageRoot
        let sources = package.appending(path: "Sources/Runtime/Resources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let css = sources.appending(path: "theme.css")
        try "blue".write(to: css, atomically: true, encoding: .utf8)
        let workspace = Workspace(configuration: fixture.configuration)
        try workspace.prepare(snapshot: SourceSnapshot.capture(configuration: fixture.configuration))
        let first = try BuildContext.capture(configuration: fixture.configuration, workspace: workspace)
        let date = try #require(try css.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try "pink".write(to: css, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: css.path)
        let changed = try BuildContext.capture(configuration: fixture.configuration, workspace: workspace)
        #expect(first.inputsHash != changed.inputsHash)
        try "blue".write(to: css, atomically: true, encoding: .utf8)
        #expect(try BuildContext.capture(configuration: fixture.configuration, workspace: workspace).fingerprint == first.fingerprint)
        try "resolved version".write(to: workspace.package.appending(path: "Package.resolved"), atomically: true, encoding: .utf8)
        let resolved = try BuildContext.capture(configuration: fixture.configuration, workspace: workspace)
        #expect(resolved.inputsHash == first.inputsHash)
        #expect(resolved.fingerprint != first.fingerprint)
    }
}

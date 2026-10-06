import Foundation
import Testing
@testable import PlaygroundCore

struct Fixture {
    let root: URL
    let source: URL
    let configuration: Configuration

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "Playground test \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appending(path: "Counter \"quoted\".swift")
        try "struct Counter {}\n".write(to: source, atomically: true, encoding: .utf8)
        configuration = try Configuration(arguments: [source.path, "--no-open", "--port", "4571"],
                                          currentDirectory: root, packageRoot: root, cacheRoot: root.appending(path: "cache"))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Playground workspace")
struct WorkspaceTests {
    @Test func configurationRejectsInvalidArguments() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        #expect(fixture.configuration.port == 4571)
        #expect(!fixture.configuration.opensBrowser)
        let relative = try Configuration(arguments: [fixture.source.lastPathComponent],
                                         currentDirectory: fixture.root, packageRoot: fixture.root)
        #expect(relative.source == fixture.configuration.source)
        for arguments in [[], [fixture.source.path, "--port", "0"], [fixture.source.path, "--port", "65536"],
                          [fixture.source.path, "--unknown"], ["missing.swift"]] {
            #expect(throws: (any Error).self) {
                try Configuration(arguments: arguments, currentDirectory: fixture.root, packageRoot: fixture.root)
            }
        }
    }

    @Test func contentSnapshotsDetectEditsAndTemplateDeletion() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let original = try SourceSnapshot.capture(configuration: fixture.configuration)
        let date = try #require(try fixture.source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try "struct Changed {}\n".write(to: fixture.source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fixture.source.path)
        let edited = try SourceSnapshot.capture(configuration: fixture.configuration)
        #expect(original.fingerprint != edited.fingerprint)
        let views = fixture.root.appending(path: "Views")
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: true)
        let template = views.appending(path: "counter.live.heex")
        try "<p>Counter</p>".write(to: template, atomically: true, encoding: .utf8)
        let added = try SourceSnapshot.capture(configuration: fixture.configuration)
        #expect(added.templates.count == 1)
        try FileManager.default.removeItem(at: template)
        let removed = try SourceSnapshot.capture(configuration: fixture.configuration)
        #expect(added.fingerprint != removed.fingerprint)
        #expect(removed.fingerprint == edited.fingerprint)
    }

    @Test func preparationEscapesPathsAndPreservesUnchangedFiles() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let workspace = Workspace(configuration: fixture.configuration)
        let snapshot = try SourceSnapshot.capture(configuration: fixture.configuration)
        try workspace.prepare(snapshot: snapshot)
        let generated = workspace.root.appending(path: "Sources/PlaygroundPage/Page.swift")
        let content = try String(contentsOf: generated, encoding: .utf8)
        #expect(content.contains("#sourceLocation(file: \(String(reflecting: fixture.source.path)), line: 1)"))
        #expect(content.hasSuffix(snapshot.source))
        let before = try generated.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try workspace.prepare(snapshot: snapshot)
        #expect(try generated.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before)
        let manifest = try String(contentsOf: workspace.root.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains("ESWBuildPlugin"))
        #expect(manifest.contains("roost-playground.git\", exact: \"\(playgroundVersion)\""))
        #expect(manifest.contains("ESW.git"))
        try "".write(to: fixture.root.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        try workspace.prepare(snapshot: snapshot)
        let checkout = try String(contentsOf: workspace.root.appending(path: "Package.swift"), encoding: .utf8)
        #expect(checkout.contains(String(reflecting: fixture.configuration.packageRoot.path)))
        let escapedPath = String(String(reflecting: fixture.configuration.source.path).dropFirst().dropLast())
        let diagnostic = "\(escapedPath):2:1: error: broken"
        #expect(workspace.mapDiagnostics(diagnostic) == "\(fixture.configuration.source.path):2:1: error: broken")
    }

    @Test func workspaceLockExcludesAnotherWriter() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let workspace = Workspace(configuration: fixture.configuration)
        var lock: WorkspaceLock? = try workspace.acquire()
        #expect(lock != nil)
        #expect(throws: (any Error).self) { try workspace.acquire() }
        lock = nil
        let replacement = try workspace.acquire()
        withExtendedLifetime(replacement) {}
    }

    @Test func inputsUseSeparateWorkspacesAndDeletedTemplatesLeaveNoGeneratedCopy() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let other = fixture.root.appending(path: "Other.swift")
        try "struct Other {}".write(to: other, atomically: true, encoding: .utf8)
        let configuration = try Configuration(arguments: [other.path], currentDirectory: fixture.root,
                                              packageRoot: fixture.root, cacheRoot: fixture.configuration.cacheRoot)
        let workspace = Workspace(configuration: fixture.configuration)
        #expect(workspace.root != Workspace(configuration: configuration).root)
        let views = fixture.configuration.views.appending(path: "nested")
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: true)
        let template = views.appending(path: "item.heex")
        try "<p>Hello</p>".write(to: template, atomically: true, encoding: .utf8)
        let snapshot = try SourceSnapshot.capture(configuration: fixture.configuration)
        #expect(snapshot.templates.keys.contains("nested/item.heex"))
        try workspace.prepare(snapshot: snapshot)
        let copy = workspace.root.appending(path: "Sources/PlaygroundPage/Views/nested/item.heex")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        try FileManager.default.removeItem(at: template)
        try workspace.prepare(snapshot: SourceSnapshot.capture(configuration: fixture.configuration))
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }
}

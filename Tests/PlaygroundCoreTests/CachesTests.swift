import Foundation
import Testing
@testable import PlaygroundCore

@Suite("Cache housekeeping")
struct CachesTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "Caches test \(UUID().uuidString)")

    private func root(_ name: String, owner: URL? = nil) throws -> URL {
        let root = base.appending(path: name)
        try FileManager.default.createDirectory(at: root.appending(path: "previews/input"), withIntermediateDirectories: true)
        if let owner { Caches.claim(root, for: owner) }
        return root
    }

    @Test func installedCopiesShareOneCacheAndClonesKeepTheirOwn() throws {
        let clone = base.appending(path: "clone")
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = clone.appending(path: "Page.swift")
        try "".write(to: source, atomically: true, encoding: .utf8)
        let installed = try Configuration(arguments: [source.path], currentDirectory: clone, packageRoot: clone)
        #expect(installed.cacheRoot == Caches.base.appending(path: "installed"))
        try "".write(to: clone.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        let checkout = try Configuration(arguments: [source.path], currentDirectory: clone, packageRoot: clone)
        #expect(checkout.cacheRoot.deletingLastPathComponent().path == Caches.base.path)
        #expect(checkout.cacheRoot.lastPathComponent != "installed")
    }

    @Test func pruneKeepsCachesSomeoneWillReuse() throws {
        let clone = FileManager.default.temporaryDirectory.appending(path: "Clone \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base); try? FileManager.default.removeItem(at: clone) }
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        try "".write(to: clone.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        let current = try root("current")
        let installed = try root("installed")
        let live = try root("live", owner: clone)
        let deleted = try root("deleted", owner: base.appending(path: "gone"))
        let legacy = try root("legacy")
        let busy = try root("busy")
        let lock = try #require(try WorkspaceLock(url: busy.appending(path: "previews/input/playground.lock")))
        defer { lock.release() }

        let removed = Caches.prune(keeping: current, base: base)
        #expect(Set(removed.map(\.lastPathComponent)) == ["deleted", "legacy"])
        for kept in [current, installed, live, busy] { #expect(FileManager.default.fileExists(atPath: kept.path)) }
        for gone in [deleted, legacy] { #expect(!FileManager.default.fileExists(atPath: gone.path)) }
        #expect(Caches.prune(keeping: URL(filePath: "/elsewhere/custom"), base: base).isEmpty, "A custom cache never prunes its siblings")
    }

    @Test func cleanRemovesEverythingNotInUse() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let idle = try root("idle")
        try Data(count: 8_192).write(to: idle.appending(path: "previews/input/artifact"))
        let busy = try root("busy")
        let lock = try #require(try WorkspaceLock(url: busy.appending(path: "previews/input/playground.lock")))
        defer { lock.release() }

        let result = Caches.clean(base: base)
        #expect(result.removed.map(\.root.lastPathComponent) == ["idle"])
        #expect(result.removed.first?.bytes ?? 0 >= 8_192)
        #expect(result.inUse.map(\.lastPathComponent) == ["busy"])
        #expect(FileManager.default.fileExists(atPath: busy.path))
    }
}

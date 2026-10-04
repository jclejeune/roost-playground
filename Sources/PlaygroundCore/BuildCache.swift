import Foundation

/// Successful executable/resource snapshots, owned by one runner holding the workspace lock.
final class BuildCache {
    let directory: URL
    private let capacity: Int
    private var entries: [String: [String]] = [:]
    private var recency: [String] = []

    init(directory: URL, capacity: Int = 8) throws {
        precondition(capacity > 0)
        self.directory = directory
        self.capacity = capacity
        // A killed runner cannot clean up. Its successor holds the same lock before getting here.
        try clear()
    }

    func lookup(_ hash: String) throws -> URL? {
        guard let files = entries[hash] else { return nil }
        let artifact = directory.appending(path: hash)
        guard FileManager.default.isExecutableFile(atPath: artifact.appending(path: "PlaygroundPage").path),
              files.allSatisfy({ FileManager.default.fileExists(atPath: artifact.appending(path: $0).path) }) else {
            try remove(hash)
            return nil
        }
        touch(hash)
        return artifact
    }

    func store(_ hash: String, from source: URL) throws {
        if entries[hash] != nil { touch(hash); return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = directory.appending(path: ".pending-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: pending) }
        try manager.copyItem(at: source, to: pending)
        let files = try manager.contentsOfDirectory(atPath: pending.path)
        guard manager.isExecutableFile(atPath: pending.appending(path: "PlaygroundPage").path) else {
            throw PlaygroundError("Cannot cache a build without its executable.")
        }
        try manager.moveItem(at: pending, to: directory.appending(path: hash))
        entries[hash] = files
        touch(hash)
        while recency.count > capacity { try remove(recency[0]) }
    }

    func remove(_ hash: String) throws {
        entries[hash] = nil
        recency.removeAll { $0 == hash }
        let artifact = directory.appending(path: hash)
        if FileManager.default.fileExists(atPath: artifact.path) {
            try FileManager.default.removeItem(at: artifact)
        }
    }

    func clear() throws {
        entries.removeAll()
        recency.removeAll()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func touch(_ hash: String) {
        recency.removeAll { $0 == hash }
        recency.append(hash)
    }
}

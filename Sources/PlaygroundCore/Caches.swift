import Foundation

/// Every playground cache lives under one folder: one per clone, named after its path, and one
/// shared by installed copies, so upgrading reuses compiled dependencies.
public enum Caches {
    public static let base = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Caches/roost-playground")
    static let installed = "installed"
    private static let owner = "owner"

    /// Records which clone a cache belongs to, so it can go once the clone is gone.
    static func claim(_ root: URL, for packageRoot: URL) {
        try? Data(packageRoot.path.utf8).write(to: root.appending(path: owner))
    }

    /// Removes caches nobody will reuse: deleted clones, earlier installed versions, and caches
    /// from before 1.0.1. A cache stays while a playground runs from it.
    // ponytail: a runner starting in another cache during this scan can lose that cache; it rebuilds.
    public static func prune(keeping current: URL, base: URL = base) -> [URL] {
        guard current.deletingLastPathComponent().standardizedFileURL.path == base.standardizedFileURL.path else { return [] }
        return roots(in: base).filter { root in
            guard root.lastPathComponent != current.lastPathComponent, root.lastPathComponent != installed,
                  !isLiveClone(root), !isInUse(root) else { return false }
            return (try? FileManager.default.removeItem(at: root)) != nil
        }
    }

    /// Removes every cache that no running playground uses.
    public static func clean(base: URL = base) -> (removed: [(root: URL, bytes: Int64)], inUse: [URL]) {
        var removed: [(root: URL, bytes: Int64)] = []
        var inUse: [URL] = []
        for root in roots(in: base) {
            if isInUse(root) { inUse.append(root); continue }
            let bytes = allocatedSize(of: root)
            if (try? FileManager.default.removeItem(at: root)) != nil { removed.append((root, bytes)) }
        }
        return (removed, inUse)
    }

    private static func roots(in base: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func isLiveClone(_ root: URL) -> Bool {
        guard let data = FileManager.default.contents(atPath: root.appending(path: owner).path) else { return false }
        return Configuration.isCheckout(URL(filePath: String(decoding: data, as: UTF8.self)))
    }

    /// A running playground holds its input's lock, and a build holds the shared package's lock.
    private static func isInUse(_ root: URL) -> Bool {
        let previews = root.appending(path: "previews")
        let inputs = (try? FileManager.default.contentsOfDirectory(at: previews, includingPropertiesForKeys: nil)) ?? []
        let locks = inputs.flatMap { [$0.appending(path: "playground.lock"), $0.appending(path: "build.lock")] }
        return locks.contains { lock in
            FileManager.default.fileExists(atPath: lock.path) && (try? WorkspaceLock(url: lock)) == nil
        }
    }

    private static func allocatedSize(of root: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}

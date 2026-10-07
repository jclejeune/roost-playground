import Foundation

public struct PlaygroundError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ message: String) { description = message }
}

public struct Configuration: Sendable {
    public let source: URL
    public let packageRoot: URL
    public let cacheRoot: URL
    public let ecosystemRoot: URL?
    public let port: Int
    public let opensBrowser: Bool
    /// `new` was given: write the starter file before watching it.
    public let createsSource: Bool
    public var views: URL { source.deletingLastPathComponent().appending(path: "Views") }
    public var address: String { "http://127.0.0.1:\(port)" }
    /// A clone compiles previews against its own sources; an installed copy fetches its release.
    public var isCheckout: Bool { Self.isCheckout(packageRoot) }

    static func isCheckout(_ packageRoot: URL) -> Bool {
        FileManager.default.fileExists(atPath: packageRoot.appending(path: "Package.swift").path)
    }

    public init(arguments: [String], currentDirectory: URL, packageRoot: URL, cacheRoot: URL? = nil,
                ecosystemRoot: URL? = nil) throws {
        var input: String?
        var port = 4567
        var opensBrowser = true
        var createsSource = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "new" where index == 0: createsSource = true
            case "--no-open": opensBrowser = false
            case "--port":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), (1...65535).contains(value) else {
                    throw PlaygroundError("--port requires a number between 1 and 65535.")
                }
                port = value
            default:
                guard !argument.hasPrefix("-"), input == nil else {
                    throw PlaygroundError("Unexpected argument: \(argument)")
                }
                input = argument
            }
            index += 1
        }
        guard let input else { throw PlaygroundError("Choose a Swift file: playground Counter.swift") }
        let directory = URL(filePath: currentDirectory.path, directoryHint: .isDirectory)
        let source = URL(filePath: input, relativeTo: directory).standardizedFileURL.resolvingSymlinksInPath()
        if createsSource {
            guard source.pathExtension == "swift" else { throw PlaygroundError("Name the new file with .swift: \(source.path)") }
            guard !FileManager.default.fileExists(atPath: source.path) else {
                throw PlaygroundError("\(source.path) already exists. Run it without `new`.")
            }
        } else {
            guard source.pathExtension == "swift",
                  (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  FileManager.default.isReadableFile(atPath: source.path) else {
                throw PlaygroundError("Expected a readable .swift file: \(source.path)")
            }
        }
        self.source = source
        self.packageRoot = packageRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.cacheRoot = cacheRoot ?? Caches.base.appending(path: Self.isCheckout(self.packageRoot)
            ? String(digest(self.packageRoot.path).prefix(16)) : Caches.installed)
        self.ecosystemRoot = ecosystemRoot
        self.port = port
        self.opensBrowser = opensBrowser
        self.createsSource = createsSource
    }
}

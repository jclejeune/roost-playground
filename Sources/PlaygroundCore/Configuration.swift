import Foundation

public struct PlaygroundError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ message: String) { description = message }
}

public struct Configuration: Sendable {
    public let source: URL
    public let packageRoot: URL
    public let cacheRoot: URL
    public let port: Int
    public let opensBrowser: Bool
    public var views: URL { source.deletingLastPathComponent().appending(path: "Views") }
    public var address: String { "http://127.0.0.1:\(port)" }

    public init(arguments: [String], currentDirectory: URL, packageRoot: URL, cacheRoot: URL? = nil) throws {
        var input: String?
        var port = 4567
        var opensBrowser = true
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
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
        guard source.pathExtension == "swift",
              (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isReadableFile(atPath: source.path) else {
            throw PlaygroundError("Expected a readable .swift file: \(source.path)")
        }
        self.source = source
        self.packageRoot = packageRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.cacheRoot = cacheRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/roost-playground/\(digest(self.packageRoot.path).prefix(16))")
        self.port = port
        self.opensBrowser = opensBrowser
    }
}

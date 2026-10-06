import Foundation

public struct PlaygroundStatus: Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case building, ready, failed, stopped }
    public var phase: Phase = .building
    public let filename: String
    public var generation = 0
    public var previewURL: String?
    public var diagnostics = ""
    /// What a running build is doing, such as "Building 312 of 1374".
    public var progress: String?
    public var buildMilliseconds: Int?
    public var buildHash: String?
    public var cacheHit = false
    public var logPath: String?

    public init(filename: String) { self.filename = filename }
}

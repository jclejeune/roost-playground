import Foundation

public struct PlaygroundStatus: Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case building, ready, failed, stopped }
    public var phase: Phase = .building
    public let filename: String
    public var generation = 0
    public var previewURL: String?
    public var diagnostics = ""
    public var buildMilliseconds: Int?
    public var buildHash: String?
    public var cacheHit = false
    public var logPath: String?

    public init(filename: String) { self.filename = filename }
}

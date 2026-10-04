import Darwin
import Foundation
import Testing
@testable import PlaygroundCore

@Suite("Owned process lifecycle")
@MainActor
struct ManagedProcessTests {
    @Test func capturesFailureWithoutPipeBackpressure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = try ManagedProcess(executable: URL(filePath: "/bin/sh"),
                                        arguments: ["-c", "yes diagnostic | head -c 100000; printf '\\nlast error\\n'; exit 7"],
                                        directory: root, log: root.appending(path: "output.log"))
        let code = try await process.wait()
        #expect(code == 7)
        let output = process.diagnostics(limit: 4096)
        #expect(output.utf8.count <= 4200)
        #expect(output.contains("last error"))
    }

    @Test func shutdownTerminatesOwnedProcessGroup() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = try ManagedProcess(executable: URL(filePath: "/bin/sh"),
                                        arguments: ["-c", "sleep 60 & wait"],
                                        directory: root, log: root.appending(path: "output.log"))
        #expect(getpgid(process.pid) == process.pid)
        #expect(process.isRunning)
        await process.stop()
        #expect(!process.isRunning)
        #expect(kill(-process.pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

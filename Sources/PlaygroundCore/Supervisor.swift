import Darwin
import Foundation

@MainActor
public final class Supervisor {
    public private(set) var status: PlaygroundStatus
    private let configuration: Configuration
    private let workspace: Workspace
    private var lease: WorkspaceLock?
    private var build: ManagedProcess?
    private var worker: Worker?
    private var candidate: Worker?
    private var binaryDirectory: URL?
    private var stopping = false

    private struct Worker {
        let process: ManagedProcess
        let executable: URL
        let address: String
    }

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        workspace = Workspace(configuration: configuration)
        lease = try workspace.acquire()
        status = PlaygroundStatus(filename: configuration.source.lastPathComponent)
    }

    public func run() async {
        var attempted: String?
        while !Task.isCancelled && !stopping {
            do {
                let snapshot = try SourceSnapshot.capture(configuration: configuration)
                if snapshot.fingerprint != attempted {
                    // Re-read after a quiet interval; editors commonly save by replacing the file.
                    try await Task.sleep(for: .milliseconds(300))
                    guard try SourceSnapshot.capture(configuration: configuration).fingerprint == snapshot.fingerprint else { continue }
                    let outcome = await rebuild(snapshot)
                    attempted = outcome == .discarded ? nil : snapshot.fingerprint
                }
                if let worker, !worker.process.isRunning {
                    fail("The preview process exited (\(worker.process.exitCode ?? -1)).\n\(worker.process.diagnostics())")
                    status.previewURL = nil
                    await retire(worker)
                    self.worker = nil
                }
            } catch is CancellationError { break }
            catch {
                attempted = nil
                fail("Cannot read the playground files. Save the file again to retry.\n\(error)")
            }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { break }
        }
        await shutdown()
    }

    public func shutdown() async {
        stopping = true
        if let build { await build.stop(); self.build = nil }
        if let candidate { await retire(candidate); self.candidate = nil }
        if let worker { await retire(worker); self.worker = nil }
        lease = nil
        status.phase = .stopped
    }

    private enum BuildOutcome { case finished, discarded }

    private func rebuild(_ snapshot: SourceSnapshot) async -> BuildOutcome {
        let start = ContinuousClock.now
        status.phase = .building
        status.diagnostics = ""
        status.buildMilliseconds = nil
        print("Building \(configuration.source.lastPathComponent)…")
        do {
            try workspace.prepare(snapshot: snapshot)
            let arguments = ["build", "--package-path", workspace.root.path, "--scratch-path", workspace.scratch.path]
            let log = workspace.logs.appending(path: "build.log")
            status.logPath = log.path
            let compiler = try ManagedProcess(executable: URL(filePath: "/usr/bin/env"),
                                              arguments: ["swift"] + arguments + ["--product", "PlaygroundPage"],
                                              directory: workspace.root, log: log)
            build = compiler
            let code = try await compiler.wait()
            await compiler.stop()
            build = nil
            try Task.checkCancellation()
            guard try isCurrent(snapshot) else { return .discarded }
            guard code == 0 else {
                let diagnostics = workspace.mapDiagnostics(compiler.diagnostics())
                throw PlaygroundError(CompilerDiagnostics.summarize(diagnostics))
            }

            if binaryDirectory == nil {
                let pathProcess = try ManagedProcess(executable: URL(filePath: "/usr/bin/env"),
                                                     arguments: ["swift"] + arguments + ["--show-bin-path"],
                                                     directory: workspace.root, log: workspace.logs.appending(path: "binary-path.log"))
                build = pathProcess
                let pathCode = try await pathProcess.wait()
                await pathProcess.stop()
                build = nil
                guard pathCode == 0 else { throw PlaygroundError(pathProcess.diagnostics()) }
                let path = pathProcess.diagnostics().trimmingCharacters(in: .whitespacesAndNewlines)
                guard path.hasPrefix("/"), !path.contains("\n") else {
                    throw PlaygroundError("Swift returned an invalid binary directory: \(path)")
                }
                binaryDirectory = URL(filePath: path)
            }
            try Task.checkCancellation()
            let token = UUID().uuidString
            let port = try availablePort()
            let executable = try workspace.stage(binaryDirectory: binaryDirectory!)
            var environment = ProcessInfo.processInfo.environment
            environment["ROOST_HOST"] = "127.0.0.1"
            environment["ROOST_PORT"] = String(port)
            environment["ROOST_PLAYGROUND_TOKEN"] = token
            environment["ROOST_PLAYGROUND_ID"] = workspace.root.lastPathComponent
            let workerLog = workspace.logs.appending(path: "preview-\(token).log")
            status.logPath = workerLog.path
            let process: ManagedProcess
            do {
                process = try ManagedProcess(executable: executable, arguments: [],
                                             directory: configuration.source.deletingLastPathComponent(),
                                             environment: environment, log: workerLog)
            } catch {
                try? FileManager.default.removeItem(at: executable.deletingLastPathComponent())
                throw error
            }
            let next = Worker(process: process, executable: executable, address: "http://127.0.0.1:\(port)")
            candidate = next
            try await waitUntilHealthy(next, token: token)
            try Task.checkCancellation()
            guard try isCurrent(snapshot) else {
                await retire(next)
                candidate = nil
                return .discarded
            }
            let previous = worker
            worker = next
            candidate = nil
            status.generation += 1
            status.previewURL = next.address + "/?build=" + token
            status.phase = .ready
            let elapsed = start.duration(to: .now).components
            status.buildMilliseconds = Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
            status.diagnostics = ""
            print("Ready at \(configuration.address) · build \(status.generation) · \(status.buildMilliseconds!) ms")
            if let previous { await retire(previous) }
            return .finished
        } catch {
            if let candidate { await retire(candidate); self.candidate = nil }
            if let build { await build.stop(); self.build = nil }
            if !Task.isCancelled && !stopping { fail(String(describing: error)) }
            return .finished
        }
    }

    private func isCurrent(_ snapshot: SourceSnapshot) throws -> Bool {
        guard !stopping else { return false }
        return try SourceSnapshot.capture(configuration: configuration).fingerprint == snapshot.fingerprint
    }

    private func fail(_ diagnostics: String) {
        if status.phase != .failed || status.diagnostics != diagnostics { print(diagnostics) }
        status.phase = .failed
        status.diagnostics = diagnostics
    }

    private func retire(_ worker: Worker) async {
        await worker.process.stop()
        try? FileManager.default.removeItem(at: worker.executable.deletingLastPathComponent())
    }

    private func waitUntilHealthy(_ worker: Worker, token: String) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard worker.process.isRunning else {
                throw PlaygroundError("The new preview exited before it was ready (\(worker.process.exitCode ?? -1)).\n\(worker.process.diagnostics())")
            }
            var request = URLRequest(url: URL(string: worker.address + "/__playground/health")!)
            request.timeoutInterval = 0.5
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               (try? JSONDecoder().decode([String: String].self, from: data))?["token"] == token {
                // A listening server whose view fails to mount is not a working preview.
                request.url = URL(string: worker.address + "/")!
                let (_, page) = try await URLSession.shared.data(for: request)
                guard (page as? HTTPURLResponse)?.statusCode == 200 else {
                    throw PlaygroundError("The new view failed to render.\n\(worker.process.diagnostics())")
                }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PlaygroundError("The new preview did not become ready within 10 seconds.\n\(worker.process.diagnostics())")
    }
}

private func availablePort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw PlaygroundError("Cannot create a loopback socket.") }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, length) == 0 ? getsockname(descriptor, $0, &length) : -1
        }
    }
    guard result == 0 else { throw PlaygroundError("Cannot reserve a loopback port.") }
    return Int(UInt16(bigEndian: address.sin_port))
}

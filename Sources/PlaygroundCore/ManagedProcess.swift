import Darwin
import Foundation

/// Each child owns a process group, including compiler subprocesses. Output goes to disk so
/// verbose builds cannot fill a pipe and deadlock the watcher.
@MainActor
public final class ManagedProcess {
    public let pid: pid_t
    public let log: URL
    private var result: Int32?

    public init(executable: URL, arguments: [String], directory: URL,
                environment: [String: String] = ProcessInfo.processInfo.environment, log: URL) throws {
        self.log = log
        let descriptor = open(log.path, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PlaygroundError("Cannot create process log: \(log.path)") }
        defer { close(descriptor) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, descriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, descriptor, STDERR_FILENO))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var signals = sigset_t()
        sigemptyset(&signals)
        try check(posix_spawnattr_setsigmask(&attributes, &signals))
        for signal in [SIGINT, SIGTERM, SIGPIPE, SIGHUP] { sigaddset(&signals, signal) }
        try check(posix_spawnattr_setsigdefault(&attributes, &signals))
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF
                                                            | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        let strings = [executable.path] + arguments
        var argv = strings.map { strdup($0) } + [nil]
        var envp = environment.keys.sorted().map { strdup("\($0)=\(environment[$0]!)") } + [nil]
        defer {
            for value in argv { free(value) }
            for value in envp { free(value) }
        }
        var child: pid_t = 0
        let code = argv.withUnsafeMutableBufferPointer { args in
            envp.withUnsafeMutableBufferPointer { env in
                posix_spawn(&child, executable.path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        try check(code)
        pid = child
    }

    public var exitCode: Int32? {
        if let result { return result }
        var status: Int32 = 0
        let reaped = waitpid(pid, &status, WNOHANG)
        if reaped == pid {
            result = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        }
        return result
    }

    public var isRunning: Bool { exitCode == nil }

    public func wait() async throws -> Int32 {
        while exitCode == nil { try await Task.sleep(for: .milliseconds(100)) }
        return exitCode!
    }

    public func diagnostics(limit: Int = 65_536) -> String {
        guard limit > 0 else { return "" }
        guard let handle = try? FileHandle(forReadingFrom: log) else { return "" }
        defer { try? handle.close() }
        do {
            let length = try handle.seekToEnd()
            let truncated = length > UInt64(limit)
            let prefix = truncated ? String("[Earlier output omitted]\n".prefix(limit)) : ""
            let budget = limit - prefix.utf8.count
            try handle.seek(toOffset: truncated ? length - UInt64(budget) : 0)
            let bytes = try handle.read(upToCount: budget) ?? Data()
            return prefix + String(decoding: bytes, as: UTF8.self)
        } catch { return "Cannot read process output: \(error)" }
    }

    public func stop() async {
        // Signal the group even if its leader exited; it may have left descendants behind.
        // macOS can briefly refuse (EPERM) a group whose child is still starting; only ESRCH means gone.
        for _ in 0..<20 {
            if kill(-pid, SIGTERM) == 0 { break }
            guard errno == EPERM else { _ = exitCode; return }
            await cleanupDelay()
        }
        for _ in 0..<20 {
            _ = exitCode
            if kill(-pid, 0) != 0 && errno == ESRCH { return }
            await cleanupDelay()
        }
        kill(-pid, SIGKILL)
        for _ in 0..<20 {
            if exitCode != nil { break }
            await cleanupDelay()
        }
    }
}

private func check(_ code: Int32) throws {
    if code != 0 { throw PlaygroundError(String(cString: strerror(code))) }
}

/// Cleanup must still wait after the supervising task has been cancelled.
private func cleanupDelay() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
    }
}

import Testing
@testable import PlaygroundCore

@Suite("Readable compiler diagnostics")
struct DiagnosticsTests {
    @Test func showsSourceErrorsBeforeDependencyWarningsAndCompilerInvocation() {
        let log = """
        warning: 'peregrine': Conflicting identity for nexus
        [Computing dependencies]
        error: SwiftCompile failed
        /original/Counter.swift:12:9: error: cannot convert String to Int
        12 | let count: Int = "oops"
           |                  `- error: cannot convert String to Int
        Failed frontend command:
        /Applications/Xcode.app/swift-frontend -c lots-of-arguments
        error: Build failed
        """
        let readable = CompilerDiagnostics.summarize(log)
        #expect(readable.hasPrefix("/original/Counter.swift:12:9: error:"))
        #expect(readable.contains("12 | let count"))
        #expect(!readable.contains("Conflicting identity"))
        #expect(!readable.contains("swift-frontend"))
    }

    @Test func keepsToolFailuresWhenNoSourceLocationExists() {
        let failure = "error: dependency resolution failed\nCould not find Package.swift"
        #expect(CompilerDiagnostics.summarize(failure) == failure)
    }

    @Test func aSourceWarningMustNotHideAnUnlocatedFailure() {
        let failure = """
        /original/Counter.swift:1:2: warning: unused variable
        error: link command failed with exit code 1
        """
        #expect(CompilerDiagnostics.summarize(failure) == failure)
    }
}

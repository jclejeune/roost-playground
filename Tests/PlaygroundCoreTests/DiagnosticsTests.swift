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

    @Test func coloredMacroErrorsAreVisibleBeforeDependencyWarnings() {
        let log = """
        warning: 'peregrine': Conflicting identity for nexus
        error: SwiftCompile failed
        macro expansion #live:14:24: \u{1B}[1;31merror: \u{1B}[1;39mcannot find 'state' in scope\u{1B}[0;0m
        `- /original/Counter.swift:53:13: \u{1B}[1;39mnote: \u{1B}[1;39mexpanded code originates here\u{1B}[0;0m
        \u{1B}[0;36m31 |\u{1B}[0;0m     func render(_: State) -> ESWLiveRender {
        \u{1B}[0;36m   |\u{1B}[0;0m     _buf.appendEscaped(\u{1B}[4;39mstate\u{1B}[0;0m.count)
        Failed frontend command:
        /Applications/Xcode.app/swift-frontend -c lots-of-arguments
        error: Build failed
        """
        let readable = CompilerDiagnostics.summarize(log)
        #expect(readable.hasPrefix("macro expansion #live:14:24: error: cannot find 'state' in scope"))
        #expect(readable.contains("/original/Counter.swift:53:13: note:"))
        #expect(readable.contains("_buf.appendEscaped(state.count)"))
        #expect(!readable.contains("\u{1B}"))
        #expect(!readable.contains("Conflicting identity"))
        #expect(!readable.contains("swift-frontend"))
    }

    @Test func coloredToolFailuresRemainReadableWithoutSourceLocations() {
        let failure = "\u{1B}[1;31merror: \u{1B}[0mlink command failed with exit code 1"
        #expect(CompilerDiagnostics.summarize(failure) == "error: link command failed with exit code 1")
    }

    @Test func progressReportsBuildStepsButNotRepositoryFetches() {
        #expect(CompilerDiagnostics.progress("Building for debugging...") == nil)
        #expect(CompilerDiagnostics.progress("Fetching https://github.com/swiftlang/swift-syntax.git") == "Fetching packages…")
        #expect(CompilerDiagnostics.progress("Computing version\n[1/83052] Fetching vapor") == "Fetching packages…")
        let build = "[1/83052] Fetching vapor\nBuilding for debugging...\n[311/1374] Compiling NIO\n[312/1374] Compiling Roost Page.swift\n"
        #expect(CompilerDiagnostics.progress(build) == "Building 312 of 1374")
        // Swift 6.4's build system separates the counter with thin spaces.
        #expect(CompilerDiagnostics.progress("[Computing dependencies]\n[5\u{2009}/\u{2009}11] SwiftSyntaxMacroExpansion") == "Building 5 of 11")
    }
}

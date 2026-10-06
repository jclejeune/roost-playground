import Foundation

enum CompilerDiagnostics {
    /// Present source diagnostics first; the complete build transcript remains in its log file.
    static func summarize(_ output: String) -> String {
        // Swift can emit terminal styling even when redirected to a file. Strip it before
        // matching locations so a colored "error:" cannot fall back to dependency warnings.
        let plain = output.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#,
                                                with: "", options: .regularExpression)
        let lines = plain.components(separatedBy: .newlines)
        var sections: [String] = []
        var current: [String] = []
        var hasSourceError = false
        func finish() {
            let section = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !section.isEmpty && !sections.contains(section) { sections.append(section) }
            current = []
        }
        for line in lines {
            if line.range(of: #":\d+:\d+: (error|warning|note):"#, options: .regularExpression) != nil {
                finish()
                current.append(line)
                if line.contains(": error:") { hasSourceError = true }
            } else if line == "Failed frontend command:" || line.hasPrefix("error:") || line.count > 2_000 {
                finish()
            } else if !current.isEmpty {
                current.append(line)
            }
        }
        finish()
        return hasSourceError ? sections.joined(separator: "\n\n") : plain
    }

    /// How far SwiftPM has got, read from the tail of its output.
    static func progress(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard let match = line.firstMatch(of: /^\[(\d+)\s*\/\s*(\d+)\] (.*)/) else { continue }
            // Repository fetches print their own [n/N] counts, which are not build steps.
            if match.3.hasPrefix("Fetching") || match.3.hasPrefix("Cloning") { return "Fetching packages…" }
            return "Building \(match.1) of \(match.2)"
        }
        return output.contains("Fetching ") || output.contains("Computing version") ? "Fetching packages…" : nil
    }
}

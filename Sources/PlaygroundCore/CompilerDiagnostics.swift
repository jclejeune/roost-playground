import Foundation

enum CompilerDiagnostics {
    /// Present source diagnostics first; the complete build transcript remains in its log file.
    static func summarize(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
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
        return hasSourceError ? sections.joined(separator: "\n\n") : output
    }
}

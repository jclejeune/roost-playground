import CryptoKit
import Foundation

func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

public struct SourceSnapshot: Sendable {
    public let source: String
    public let templates: [String: String]
    public let fingerprint: String

    public static func capture(configuration: Configuration) throws -> Self {
        let source = try String(contentsOf: configuration.source, encoding: .utf8)
        var templates: [String: String] = [:]
        let manager = FileManager.default
        if manager.fileExists(atPath: configuration.views.path) {
            guard let files = manager.enumerator(atPath: configuration.views.path) else {
                throw PlaygroundError("Cannot read templates at \(configuration.views.path)")
            }
            // DirectoryEnumerator supplies relative names directly. Cutting an absolute URL by
            // string length fails when Foundation canonicalizes /var to /private/var on macOS.
            for case let relative as String in files {
                guard !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { continue }
                let file = configuration.views.appending(path: relative)
                guard ["esw", "heex"].contains(file.pathExtension) else { continue }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                templates[relative] = try String(contentsOf: file, encoding: .utf8)
            }
        }
        // Length prefixes keep different filenames and contents from producing ambiguous input.
        var content = "\(source.utf8.count):\(source)"
        for path in templates.keys.sorted() {
            let template = templates[path]!
            content += "\(path.utf8.count):\(path)\(template.utf8.count):\(template)"
        }
        return Self(source: source, templates: templates, fingerprint: digest(content))
    }
}

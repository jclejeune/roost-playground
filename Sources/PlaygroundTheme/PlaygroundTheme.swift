import Foundation

/// The Roost demo's visual foundation, shared by the runner and its standalone previews.
package enum PlaygroundTheme {
    package static let stylesheet = String(decoding: resource("roost.css"), as: UTF8.self)
    package static let logo = resource("roost.png")

    private static func resource(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing bundled Roost theme resource: \(name)")
        }
        return data
    }
}

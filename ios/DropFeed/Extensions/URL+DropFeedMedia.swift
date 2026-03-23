import Foundation

extension URL {
    /// Resy/CDN URLs are often protocol-relative (`//images.ctfassets.net/...`); `URL(string:)` fails without a scheme.
    init?(dropFeedMediaString string: String) {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("//") {
            self.init(string: "https:\(t)")
        } else {
            self.init(string: t)
        }
    }
}

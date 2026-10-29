import Foundation
import SnapgrokCore

struct LinkPaste {
    /// Shown if the composer only accepts plain text. A short URL that redirects to `href`.
    var plain: String
    /// Rich link. The label is short and the href is the original page.
    var html: String
}

enum ShortLink {
    /// A tiny label that still points at the exact page, query string included.
    static func paste(url: String) async -> LinkPaste {
        let full = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = await compress(full)
        return LinkPaste(plain: label, html: PageLink.html(label: label, href: full))
    }

    private static func compress(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: "https://is.gd/create.php") else { return trimmed }
        components.queryItems = [
            URLQueryItem(name: "format", value: "simple"),
            URLQueryItem(name: "url", value: trimmed),
        ]
        guard let endpoint = components.url else { return trimmed }
        var request = URLRequest(url: endpoint, timeoutInterval: 4)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let short = URL(string: text),
              short.scheme == "https",
              short.host == "is.gd",
              text.hasPrefix("https://is.gd/") else {
            return trimmed
        }
        return text
    }
}

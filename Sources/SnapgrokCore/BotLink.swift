import Foundation

public enum BotLink {
    /// Pulls a Grok Bot agent id out of a copied link or a bare id.
    /// Accepts `https://x.ai/bot/agent/{id}`, `grokbot://app/v1/agent?id={id}`,
    /// and the same id on the `sand://` scheme.
    public static func agentID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed), components.scheme != nil {
            if let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let valid = validate(id) {
                return valid
            }
            let parts = components.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[parts.count - 2] == "agent" {
                return validate(parts[parts.count - 1])
            }
            return nil
        }

        return validateBare(trimmed)
    }

    private static func validate(_ id: String) -> String? {
        guard id.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    /// A pasted word with no URL must look like an id. Plain names such as "Research" are rejected.
    private static func validateBare(_ id: String) -> String? {
        guard let valid = validate(id), valid.count >= 8 else { return nil }
        guard valid.contains(where: { $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return valid
    }
}

public enum PageLink {
    /// A markdown link. The href must be the real page, or a short link that redirects to it.
    public static func markdown(title: String, href: String) -> String {
        let label = title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        if label.isEmpty || label == href {
            return "<\(href)>"
        }
        return "[\(label)](\(href))"
    }

    /// HTML anchor. The visible label can be a short URL while href stays the real page.
    public static func html(label: String, href: String) -> String {
        "<a href=\"\(escape(href))\">\(escape(label))</a>"
    }

    private static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

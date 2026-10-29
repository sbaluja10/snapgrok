import Foundation

public enum AgentRoster {
    /// Parses a `ListGrokBotAgents` JSON body into the bots Snapgrok can open.
    public static func bots(from data: Data) -> [Bot] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agents = json["agents"] as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        var bots: [Bot] = []
        for agent in agents {
            guard let id = agentID(in: agent), seen.insert(id).inserted else { continue }
            bots.append(Bot(id: id, name: displayName(in: agent, id: id)))
        }
        return bots.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func agentID(in agent: [String: Any]) -> String? {
        for key in ["agentId", "agent_id", "id"] {
            if let raw = agent[key] as? String, let id = BotLink.agentID(from: raw) {
                return id
            }
        }
        return nil
    }

    private static func displayName(in agent: [String: Any], id: String) -> String {
        for key in ["name", "title"] {
            if let raw = agent[key] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return String(trimmed.prefix(60))
                }
            }
        }
        return "Bot \(id.suffix(6))"
    }
}

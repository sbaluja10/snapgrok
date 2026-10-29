import Foundation
import Observation

public struct Bot: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@MainActor
@Observable
public final class BotStore {
    public private(set) var bots: [Bot] = []
    private let fileURL: URL

    public init(fileURL: URL = BotStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    public static var defaultFileURL: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("snapgrok", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("bots.json")
    }

    public func upsert(name: String, link: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BotStoreError.missingName
        }
        guard trimmedName.count <= 60 else {
            throw BotStoreError.nameTooLong
        }
        guard let id = BotLink.agentID(from: link) else {
            throw BotStoreError.invalidLink
        }
        if let index = bots.firstIndex(where: { $0.id == id }) {
            bots[index].name = trimmedName
        } else {
            bots.append(Bot(id: id, name: trimmedName))
        }
        try save()
    }

    public func remove(id: String) {
        bots.removeAll { $0.id == id }
        try? save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([Bot].self, from: data) else { return }
        bots = decoded.filter { BotLink.agentID(from: $0.id) != nil && !$0.name.isEmpty }
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bots)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum BotStoreError: LocalizedError, Equatable {
    case missingName
    case nameTooLong
    case invalidLink

    public var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter a name for this bot."
        case .nameTooLong:
            "Use a name of 60 characters or fewer."
        case .invalidLink:
            "That isn’t a Grok Bot link. Paste a link like https://x.ai/bot/agent/… or grokbot://app/v1/agent?id=…"
        }
    }
}

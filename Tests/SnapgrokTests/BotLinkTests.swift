import XCTest
@testable import SnapgrokCore

final class BotLinkTests: XCTestCase {
    func testParsesWebAgentLink() {
        XCTAssertEqual(
            BotLink.agentID(from: "https://x.ai/bot/agent/Abcd_efgh-12345678"),
            "Abcd_efgh-12345678"
        )
    }

    func testParsesGrokbotScheme() {
        XCTAssertEqual(
            BotLink.agentID(from: "grokbot://app/v1/agent?id=Abcd_efgh-12345678"),
            "Abcd_efgh-12345678"
        )
    }

    func testParsesSandSchemeAndCursorLink() {
        XCTAssertEqual(
            BotLink.agentID(from: "sand://app/v1/agent?id=bot_id_01"),
            "bot_id_01"
        )
        XCTAssertEqual(
            BotLink.agentID(from: "https://cursor.com/grok-bot/link/v1/agent?id=bot_id_01&open=1"),
            "bot_id_01"
        )
    }

    func testParsesBareIDAndRejectsNames() {
        XCTAssertEqual(BotLink.agentID(from: "  bot_id_01  "), "bot_id_01")
        XCTAssertNil(BotLink.agentID(from: "Research"))
        XCTAssertNil(BotLink.agentID(from: ""))
        XCTAssertNil(BotLink.agentID(from: "https://x.ai/bot/agent"))
    }
}

final class PageLinkTests: XCTestCase {
    func testFormatsAMarkdownLink() {
        XCTAssertEqual(
            PageLink.markdown(title: "Example", href: "https://example.com/s/abcd"),
            "[Example](https://example.com/s/abcd)"
        )
        XCTAssertEqual(
            PageLink.markdown(title: "  ", href: "https://example.com/s/abcd"),
            "<https://example.com/s/abcd>"
        )
        XCTAssertEqual(
            PageLink.html(
                label: "https://example.com/s/abcd",
                href: "https://example.com/page?locale=en&preview=1"
            ),
            "<a href=\"https://example.com/page?locale=en&amp;preview=1\">https://example.com/s/abcd</a>"
        )
    }
}

final class AgentRosterTests: XCTestCase {
    func testParsesAgentNamesAndIds() throws {
        let json = """
        {"agents":[
          {"agentId":"bot_id_01","name":"Research","title":"Ignored"},
          {"agent_id":"bot_id_02","name":"","title":"Writer"},
          {"id":"not an id","name":"Skip"}
        ]}
        """.data(using: .utf8)!
        let bots = AgentRoster.bots(from: json)
        XCTAssertEqual(bots.map(\.name), ["Research", "Writer"])
        XCTAssertEqual(bots.map(\.id), ["bot_id_01", "bot_id_02"])
    }
}

final class BotStoreTests: XCTestCase {
    @MainActor
    func testUpsertAndRemove() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapgrok-tests-\(UUID().uuidString)")
            .appendingPathComponent("bots.json")
        let store = BotStore(fileURL: url)
        try store.upsert(name: "Research", link: "https://x.ai/bot/agent/Abcd_efgh-12345678")
        try store.upsert(name: "Research bot", link: "grokbot://app/v1/agent?id=Abcd_efgh-12345678")
        XCTAssertEqual(store.bots.map(\.name), ["Research bot"])

        let reloaded = BotStore(fileURL: url)
        XCTAssertEqual(reloaded.bots.map(\.id), ["Abcd_efgh-12345678"])

        reloaded.remove(id: "Abcd_efgh-12345678")
        XCTAssertTrue(BotStore(fileURL: url).bots.isEmpty)
    }

    @MainActor
    func testRejectsANameUsedAsTheLink() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapgrok-tests-\(UUID().uuidString).json")
        let store = BotStore(fileURL: url)
        XCTAssertThrowsError(try store.upsert(name: "Research", link: "Research")) { error in
            XCTAssertEqual(error as? BotStoreError, .invalidLink)
        }
    }
}

import AppKit
import ApplicationServices
import Carbon

enum SendError: LocalizedError {
    case grokBotMissing
    case accessibility
    case didNotFocus
    case lostFocus

    var errorDescription: String? {
        switch self {
        case .grokBotMissing:
            "Grok Bot isn’t installed. Snapgrok opens it with a grokbot:// link, then pastes the page into the composer."
        case .accessibility:
            "The page is open in Grok Bot. To paste the screenshot, turn Snapgrok off and back on in System Settings → Privacy & Security → Accessibility, quit Snapgrok, open it again, then press ⌥⇧G."
        case .didNotFocus:
            "Grok Bot didn’t come to the front, so nothing was pasted."
        case .lostFocus:
            "Grok Bot moved to the background before the preview was ready."
        }
    }
}

enum GrokSender {
    private static let bundleID = "com.anysphere.sand"
    private static let focusPrompt = CGKeyCode(kVK_ANSI_I)
    private static let selectAll = CGKeyCode(kVK_ANSI_A)
    private static let paste = CGKeyCode(kVK_ANSI_V)
    private static let delete = CGKeyCode(kVK_Delete)

    /// Opens the bot with the page staged in the composer. Return is left for the user.
    @MainActor
    static func stage(botID: String, message: String, html: String, pngData: Data) async throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            throw SendError.grokBotMissing
        }

        let coldStart = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        guard let url = previewURL(botID: botID, message: message) else {
            throw SendError.didNotFocus
        }

        try writeImage(pngData)
        try await revealGrok(url)
        guard trustedForKeystrokes() else {
            throw SendError.accessibility
        }

        guard await waitUntilFront(timeout: coldStart ? 12 : 6) else {
            throw SendError.didNotFocus
        }
        try await pause(coldStart ? 1.2 : 0.45)
        try await requireFront(.didNotFocus)

        tap(focusPrompt, command: true)
        try await pause(0.25)
        try await requireFront(.didNotFocus)
        tap(selectAll, command: true)
        try await pause(0.08)
        try await requireFront(.didNotFocus)
        tap(delete)
        try await pause(0.08)

        try writeImage(pngData)
        try await requireFront(.didNotFocus)
        tap(paste, command: true)
        try await pause(0.45)

        writeLink(plain: message, html: html)
        try await requireFront(.lostFocus)
        tap(paste, command: true)
    }

    private static func revealGrok(_ url: URL) async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw SendError.grokBotMissing
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.open(url, configuration: configuration)
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.unhide()
            running.activate(options: [.activateAllWindows])
        } else {
            let launch = NSWorkspace.OpenConfiguration()
            launch.activates = true
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: launch)
        }
        NSAppleScript(source: "tell application id \"com.anysphere.sand\" to activate")?.executeAndReturnError(nil)
    }

    private static func previewURL(botID: String, message: String) -> URL? {
        var components = URLComponents()
        components.scheme = "grokbot"
        components.host = "app"
        components.path = "/v1/prompt"
        components.queryItems = [
            URLQueryItem(name: "id", value: botID),
            URLQueryItem(name: "text", value: String(message.prefix(1000))),
        ]
        return components.url
    }

    private static func requireFront(_ error: SendError) async throws {
        guard isFront else { throw error }
    }

    private static var isFront: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func trustedForKeystrokes() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func waitUntilFront(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isFront { return true }
            try? await pause(0.1)
        }
        return false
    }

    private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Grok Bot attachments are files. Offer both the PNG bytes and a file URL so the composer can take either.
    private static func writeImage(_ data: Data) throws {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("snapgrok/captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("latest.png")
        try data.write(to: file, options: .atomic)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.addTypes([.png], owner: nil)
        pasteboard.setData(data, forType: .png)
    }

    private static func writeLink(plain: String, html: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.html, .string], owner: nil)
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(plain, forType: .string)
    }

    private static func tap(_ key: CGKeyCode, command: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags: CGEventFlags = command ? .maskCommand : []
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

import AppKit
import ApplicationServices
import ServiceManagement
import SnapgrokCore
import SwiftUI

@MainActor
final class AppController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    static let shared = AppController()

    private let account = GrokAccount()
    private let hotkey = HotkeyCenter()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var sendPanel: NSWindow?
    private var botsPanel: NSWindow?
    private let menuBarPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        return popover
    }()
    private var latestCapture: PageCapture?
    private var isBusy = false

    func start() {
        statusItem.isVisible = true
        setStatus(nil)
        // Cursor's menu bar icon shows and focuses its window. A status menu
        // hands focus back to Chrome, so the window never stays in front.
        menuBarPopover.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        hotkey.setHandler {
            Task { @MainActor in
                AppController.shared.captureAndAsk(requireChromeFrontmost: true)
            }
        }
        hotkey.install()
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        Task { @MainActor in
            await account.restore()
            if account.status != .ready {
                showBots()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popMenu()
            return
        }
        if menuBarPopover.isShown {
            menuBarPopover.performClose(nil)
            return
        }
        showBots()
    }

    private func popMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.delegate = self
        menuWillOpen(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let send = menu.addItem(withTitle: "Snap Front Chrome Tab…", action: #selector(captureFromMenu), keyEquivalent: "")
        send.target = self
        menu.addItem(NSMenuItem.separator())
        let bots = menu.addItem(withTitle: "Bots…", action: #selector(showBots), keyEquivalent: "")
        bots.target = self
        let login = menu.addItem(
            withTitle: "Launch at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(NSMenuItem.separator())
        let shortcut = menu.addItem(withTitle: "Shortcut is ⌥⇧G", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(NSMenuItem.separator())
        let quit = menu.addItem(withTitle: "Quit Snapgrok", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
    }

    @objc private func captureFromMenu() {
        captureAndAsk(requireChromeFrontmost: false)
    }

    private func captureAndAsk(requireChromeFrontmost: Bool) {
        if let sendPanel, sendPanel.isVisible {
            reveal(sendPanel)
            return
        }
        guard !isBusy else { return }
        isBusy = true
        setStatus("…")
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let capture = try await ChromeCapture.take(requireChromeFrontmost: requireChromeFrontmost)
                latestCapture = capture
                if let bot = rememberedBot() {
                    try await send(capture, to: bot)
                } else {
                    presentSend(capture)
                }
                setStatus(nil)
            } catch SendError.accessibility {
                setStatus("Allow Accessibility")
            } catch let error as SendError {
                setStatus(nil)
                alert(title: "Couldn’t open your bot", message: error.localizedDescription)
            } catch {
                setStatus(nil)
                alert(title: "Couldn’t capture Chrome", message: error.localizedDescription)
            }
        }
    }

    private func presentSend(_ capture: PageCapture) {
        let session = SendSession(capture: capture, account: account) { [weak self] bot in
            self?.deliver(capture, to: bot)
        } onCancel: { [weak self] in
            self?.sendPanel?.close()
            self?.sendPanel = nil
        }
        sendPanel?.close()
        let panel = panel(title: "Snap", view: SendPanelView(session: session), size: NSSize(width: 520, height: 680))
        sendPanel = panel
        reveal(panel)
    }

    private func rememberedBot() -> Bot? {
        guard let id = UserDefaults.standard.string(forKey: "lastBotID"), !id.isEmpty else { return nil }
        if let bot = account.bots.first(where: { $0.id == id }) {
            return bot
        }
        if account.status == .ready, !account.bots.isEmpty {
            return nil
        }
        return Bot(id: id, name: "your bot")
    }

    private func deliver(_ capture: PageCapture, to bot: Bot) {
        sendPanel?.close()
        sendPanel = nil
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await send(capture, to: bot)
                setStatus(nil)
            } catch SendError.accessibility {
                setStatus("Allow Accessibility")
            } catch {
                setStatus(nil)
                alert(title: "Couldn’t open \(bot.name)", message: error.localizedDescription)
            }
        }
    }

    private func send(_ capture: PageCapture, to bot: Bot) async throws {
        setStatus("Opening")
        let link = await ShortLink.paste(url: capture.url)
        try await GrokSender.stage(botID: bot.id, message: link.plain, html: link.html, pngData: capture.pngData)
    }

    @objc private func showBots() {
        guard let button = statusItem.button else { return }
        if menuBarPopover.isShown {
            menuBarPopover.performClose(nil)
            return
        }
        if menuBarPopover.contentViewController == nil {
            let host = NSHostingController(rootView: BotsSettingsView(account: account) { bot in
                AppController.shared.chooseBot(bot)
            })
            // The popover already insets for its arrow. Extra safe area pushes
            // the title up into that arrow and clips it.
            host.safeAreaRegions = []
            host.sizingOptions = [.preferredContentSize]
            menuBarPopover.contentViewController = host
        }
        fitMenuBarPopover()
        // A popover anchored to the status item is what stays above Chrome.
        // A normal window is ordered behind the front app as soon as the click ends.
        menuBarPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        liftMenuBarPopover()
    }

    private func fitMenuBarPopover() {
        guard let host = menuBarPopover.contentViewController as? NSHostingController<BotsSettingsView> else { return }
        var size = host.sizeThatFits(in: NSSize(width: 300, height: 640))
        if size.height < 80 { size.height = 220 }
        size.width = 300
        size.height = min(size.height, 640)
        host.preferredContentSize = size
        menuBarPopover.contentSize = size
    }

    func popoverDidShow(_ notification: Notification) {
        fitMenuBarPopover()
        liftMenuBarPopover()
    }

    private func liftMenuBarPopover() {
        guard let window = menuBarPopover.contentViewController?.view.window else { return }
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
    }

    private func chooseBot(_ bot: Bot) {
        UserDefaults.standard.set(bot.id, forKey: "lastBotID")
        menuBarPopover.performClose(nil)
        guard let latestCapture else { return }
        deliver(latestCapture, to: bot)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            alert(title: "Couldn’t change login item", message: error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setStatus(_ text: String?) {
        let button = statusItem.button
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapgrok")
            ?? NSImage(systemSymbolName: "camera", accessibilityDescription: "Snapgrok")
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        button?.image = image
        button?.imagePosition = .imageLeading
        button?.title = text ?? "Snapgrok"
    }

    private func panel<V: View>(title: String, view: V, size: NSSize = NSSize(width: 460, height: 520)) -> NSPanel {
        let host = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentViewController = host
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setContentSize(size)
        return panel
    }

    /// Codex brings its hotkey window forward with a focus steal. A floating panel
    /// stays behind Chrome, and clicks on it never reach the bot buttons.
    private func reveal(_ window: NSWindow) {
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        placeUnderMenuBar(window)
        bringForward(window)
    }

    private func placeUnderMenuBar(_ window: NSWindow) {
        let size = window.frame.size
        guard let button = statusItem.button, let buttonWindow = button.window else {
            window.center()
            return
        }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height - 6
        )
        let screen = NSScreen.screens.first { $0.frame.contains(buttonFrame.origin) } ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        window.setFrameOrigin(origin)
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private func alert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        NSAppleScript(source: "tell application \"Snapgrok\" to activate")?.executeAndReturnError(nil)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppController.shared.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

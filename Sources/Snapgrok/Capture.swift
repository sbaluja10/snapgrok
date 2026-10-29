import AppKit
import ScreenCaptureKit

struct PageCapture {
    let title: String
    let url: String
    let image: NSImage
    let pngData: Data

    var message: String {
        url
    }
}

enum CaptureError: LocalizedError {
    case notChrome
    case chrome(String)
    case noWindow
    case screenPermission
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .notChrome:
            "Switch to the Chrome window you want, then press ⌥⇧G again."
        case .chrome(let message):
            message
        case .noWindow:
            "Chrome is in front, but Snapgrok couldn’t find a window large enough to capture."
        case .screenPermission:
            "Turn Snapgrok on under System Settings → Privacy & Security → Screen & System Audio Recording, quit Snapgrok, open it again, then press ⌥⇧G."
        case .unreadableImage:
            "The screenshot couldn’t be saved."
        }
    }
}

enum ChromeCapture {
    private static let chromeBundleID = "com.google.Chrome"

    @MainActor
    static func take(requireChromeFrontmost: Bool) async throws -> PageCapture {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if requireChromeFrontmost, front != chromeBundleID {
            throw CaptureError.notChrome
        }
        let tab = try frontTab()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if Self.looksLikeScreenPermission(error) {
                CGRequestScreenCaptureAccess()
                throw CaptureError.screenPermission
            }
            throw CaptureError.chrome(error.localizedDescription)
        }
        guard let window = frontChromeWindow(in: content) else {
            throw CaptureError.noWindow
        }

        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard let pngData = pngData(from: cgImage) else {
            throw CaptureError.unreadableImage
        }
        return PageCapture(
            title: tab.title,
            url: tab.url,
            image: NSImage(data: pngData) ?? NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            pngData: pngData
        )
    }

    private static func looksLikeScreenPermission(_ error: Error) -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("permission") || text.contains("declined") || text.contains("not authorized") || text.contains("tcc")
    }

    private static func frontTab() throws -> (title: String, url: String) {
        let source = """
        tell application "Google Chrome"
            if (count of windows) is 0 then error "Chrome has no windows open."
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & linefeed & tabURL
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            let message = error?[NSAppleScript.errorMessage] as? String
                ?? "Chrome didn’t share the front tab. Allow Snapgrok to control Google Chrome when macOS asks."
            throw CaptureError.chrome(message)
        }
        let lines = result.stringValue?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []
        guard let url = lines.last, url.contains("://") || url.hasPrefix("about:") || url.hasPrefix("chrome:") else {
            throw CaptureError.chrome("Chrome didn’t return an address for the front tab.")
        }
        let title = lines.dropLast().joined(separator: "\n")
        return (title, url)
    }

    private static func frontChromeWindow(in content: SCShareableContent) -> SCWindow? {
        let chrome = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == chromeBundleID
                && window.isOnScreen
                && window.frame.width > 240
                && window.frame.height > 160
        }
        guard !chrome.isEmpty else { return nil }

        let orderedIDs = windowIDsFrontToBack()
        if let match = orderedIDs.compactMap({ id in chrome.first { $0.windowID == id } }).first {
            return match
        }
        return chrome.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func windowIDsFrontToBack() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            let owner = info[kCGWindowOwnerName as String] as? String
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard owner == "Google Chrome", layer == 0 else { return nil }
            guard let number = info[kCGWindowNumber as String] as? UInt32 else { return nil }
            return number
        }
    }

    private static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}

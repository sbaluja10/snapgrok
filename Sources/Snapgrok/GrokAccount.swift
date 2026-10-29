import AppKit
import CryptoKit
import Foundation
import Security
import SnapgrokCore

@MainActor
@Observable
final class GrokAccount {
    private(set) var bots: [Bot] = []
    private(set) var status: Status = .signedOut
    private(set) var accountLabel: String?
    private var signInTask: Task<Void, Never>?

    enum Status: Equatable {
        case signedOut
        case waitingForBrowser
        case loadingBots
        case ready
        case failed(String)
    }

    var isSignedIn: Bool {
        switch status {
        case .loadingBots, .ready:
            true
        case .signedOut, .waitingForBrowser, .failed:
            false
        }
    }

    func restore() async {
        guard let session = SessionStore.load() else {
            status = .signedOut
            return
        }
        accountLabel = SessionEmail.label(in: session.accessToken)
        await loadBots(session: session)
    }

    func signIn() {
        guard signInTask == nil else { return }
        status = .waitingForBrowser
        signInTask = Task { [weak self] in
            guard let self else { return }
            defer { self.signInTask = nil }
            do {
                let session = try await CursorLogin.signIn()
                if Task.isCancelled { return }
                try SessionStore.save(session)
                self.accountLabel = SessionEmail.label(in: session.accessToken)
                await self.loadBots(session: session)
            } catch is CancellationError {
                if self.status == .waitingForBrowser {
                    self.status = .signedOut
                }
            } catch {
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        if status == .waitingForBrowser {
            status = .signedOut
        }
    }

    func reload() async {
        guard let session = SessionStore.load() else {
            status = .signedOut
            bots = []
            return
        }
        await loadBots(session: session)
    }

    func signOut() {
        cancelSignIn()
        SessionStore.delete()
        bots = []
        accountLabel = nil
        status = .signedOut
    }

    private func loadBots(session: StoredSession) async {
        status = .loadingBots
        do {
            let data = try await CursorLogin.listAgents(accessToken: session.accessToken)
            bots = AgentRoster.bots(from: data)
            status = .ready
        } catch let error as AccountError where error == .signedOut {
            SessionStore.delete()
            bots = []
            accountLabel = nil
            status = .failed("That sign-in expired. Sign in again.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

enum AccountError: LocalizedError, Equatable {
    case signedOut
    case timedOut
    case cancelled
    case couldNotSave
    case botsUnavailable

    var errorDescription: String? {
        switch self {
        case .signedOut:
            "Sign in to the account you use for Grok Bot."
        case .timedOut:
            "Sign-in timed out. Finish it in the browser, then try again."
        case .cancelled:
            "Sign-in was cancelled."
        case .couldNotSave:
            "Snapgrok couldn’t save the sign-in in the Keychain."
        case .botsUnavailable:
            "Grok Bot didn’t return your bots."
        }
    }
}

enum CursorLogin {
    private static let website = URL(string: "https://cursor.com")!
    private static let api = URL(string: "https://api2.cursor.sh")!

    static func signIn() async throws -> StoredSession {
        let verifier = base64url(randomBytes(count: 32))
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let uuid = UUID().uuidString.lowercased()
        var login = URLComponents(url: website.appendingPathComponent("loginDeepControl"), resolvingAgainstBaseURL: false)!
        login.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: "cli"),
        ]
        guard let loginURL = login.url else { throw AccountError.botsUnavailable }
        NSWorkspace.shared.open(loginURL)

        var poll = URLComponents(url: api.appendingPathComponent("auth/poll"), resolvingAgainstBaseURL: false)!
        poll.queryItems = [
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "verifier", value: verifier),
        ]
        guard let pollURL = poll.url else { throw AccountError.botsUnavailable }

        // The browser login completes out of process. 404 means it is still waiting.
        for _ in 0..<90 {
            try Task.checkCancellation()
            var request = URLRequest(url: pollURL)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            if code == 200, let session = StoredSession(json: data) {
                return session
            }
            throw AccountError.botsUnavailable
        }
        throw AccountError.timedOut
    }

    static func listAgents(accessToken: String) async throws -> Data {
        let url = api.appendingPathComponent("aiserver.v1.GrokBotService/ListGrokBotAgents")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("sand-desktop", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("true", forHTTPHeaderField: "x-ghost-mode")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 {
            throw AccountError.signedOut
        }
        guard (200..<300).contains(code) else {
            throw AccountError.botsUnavailable
        }
        return data
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct StoredSession: Codable {
    var accessToken: String
    var refreshToken: String

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let accessToken = object["accessToken"] as? String, !accessToken.isEmpty,
              let refreshToken = object["refreshToken"] as? String, !refreshToken.isEmpty else {
            return nil
        }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

enum SessionStore {
    private static let service = "local.snapgrok"
    private static let account = "grok-bot"

    static func load() -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            return nil
        }
        return session
    }

    static func save(_ session: StoredSession) throws {
        guard let data = try? JSONEncoder().encode(session) else { throw AccountError.couldNotSave }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw AccountError.couldNotSave
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum SessionEmail {
    static func label(in token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let email = json["email"] as? String, email.contains("@") {
            return email
        }
        return nil
    }
}

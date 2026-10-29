import AppKit
import SnapgrokCore
import SwiftUI

@MainActor
@Observable
final class SendSession {
    let capture: PageCapture
    var selection: String?
    let account: GrokAccount
    private let onSend: (Bot) -> Void
    private let onCancel: () -> Void

    var bots: [Bot] { account.bots }

    init(capture: PageCapture, account: GrokAccount, onSend: @escaping (Bot) -> Void, onCancel: @escaping () -> Void) {
        self.capture = capture
        self.account = account
        self.onSend = onSend
        self.onCancel = onCancel
        chooseSelection()
    }

    func chooseSelection() {
        let last = UserDefaults.standard.string(forKey: "lastBotID")
        if let last, account.bots.contains(where: { $0.id == last }) {
            selection = last
        } else if selection == nil || account.bots.contains(where: { $0.id == selection }) == false {
            selection = account.bots.first?.id
        }
    }

    func open(_ bot: Bot) {
        UserDefaults.standard.set(bot.id, forKey: "lastBotID")
        selection = bot.id
        onSend(bot)
    }

    var favorite: Bot? {
        if let selection, let bot = account.bots.first(where: { $0.id == selection }) {
            return bot
        }
        return account.bots.first
    }

    func cancel() {
        onCancel()
    }
}

struct SendPanelView: View {
    @Bindable var session: SendSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SNAP")
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                Spacer()
                Text(pageHost)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(nsImage: session.capture.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 210)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.capture.title.isEmpty ? "This page" : session.capture.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(session.capture.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            accountBody
        }
        .padding(18)
        .frame(width: 500)
        .onChange(of: session.account.bots.map(\.id)) { _, _ in
            session.chooseSelection()
        }
    }

    @ViewBuilder
    private var accountBody: some View {
        switch session.account.status {
        case .signedOut, .failed:
            AccountBotList(account: session.account, selection: .constant(nil))
        case .waitingForBrowser, .loadingBots:
            AccountBotList(account: session.account, selection: .constant(nil))
        case .ready:
            if let favorite = session.favorite {
                Button {
                    session.open(favorite)
                } label: {
                    HStack(spacing: 12) {
                        BotMark(name: favorite.name, prominent: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preview with")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(favorite.name)
                                .font(.title2.weight(.bold))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.title3.weight(.semibold))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SnapButtonStyle(ink: BotInk.color(for: favorite.id), prominent: true))
                .contentShape(Rectangle())
                .keyboardShortcut(.defaultAction)

                let others = session.bots.filter { $0.id != favorite.id }
                if !others.isEmpty {
                    Text("Or someone else")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(others) { bot in
                            Button(bot.name) { session.open(bot) }
                                .buttonStyle(SnapButtonStyle(ink: BotInk.color(for: bot.id), prominent: false))
                                .contentShape(Rectangle())
                        }
                    }
                }
                Text("Lands in Grok Bot for you to send. Return uses \(favorite.name) next time too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Not now", action: session.cancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
                Spacer()
            }
        }
    }

    private var pageHost: String {
        URL(string: session.capture.url)?.host() ?? session.capture.url
    }
}

private enum BotInk {
    private static let palette: [Color] = [
        Color(red: 0.86, green: 0.28, blue: 0.22),
        Color(red: 0.16, green: 0.42, blue: 0.78),
        Color(red: 0.10, green: 0.52, blue: 0.40),
        Color(red: 0.76, green: 0.42, blue: 0.10),
        Color(red: 0.46, green: 0.30, blue: 0.72),
    ]

    static func color(for id: String) -> Color {
        let index = id.utf8.reduce(0) { $0 + Int($1) } % palette.count
        return palette[index]
    }
}

private struct BotMark: View {
    var name: String
    var prominent: Bool

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(prominent ? .title2.weight(.bold) : .body.weight(.bold))
            .frame(width: prominent ? 44 : 28, height: prominent ? 44 : 28)
            .background(.white.opacity(0.28), in: Circle())
    }
}

private struct SnapButtonStyle: ButtonStyle {
    var ink: Color
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, prominent ? 4 : 12)
            .padding(.vertical, prominent ? 2 : 8)
            .foregroundStyle(.primary)
            .background(ink.opacity(configuration.isPressed ? 0.42 : prominent ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: prominent ? 18 : 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.35), value: configuration.isPressed)
    }
}

struct BotsSettingsView: View {
    @Bindable var account: GrokAccount
    var onChoose: (Bot) -> Void
    @AppStorage("lastBotID") private var selectedID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bots")
                .font(.headline)
            bodyContent
        }
        .padding(14)
        .frame(width: 300, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch account.status {
        case .signedOut:
            Text("Sign in with the account you use for Grok Bot.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign in") { account.signIn() }
        case .waitingForBrowser:
            Text("Finish signing in in the browser. Your bots show up here when that’s done.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel", action: account.cancelSignIn)
        case .loadingBots:
            ProgressView("Loading your bots…")
                .controlSize(.small)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign in") { account.signIn() }
        case .ready:
            Text("⌥⇧G uses the checked bot.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if account.bots.isEmpty {
                Text("This account has no bots yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let rowHeight: CGFloat = 32
                let height = min(CGFloat(account.bots.count) * rowHeight, 320)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(account.bots) { bot in
                            Button {
                                onChoose(bot)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(bot.name)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if bot.id == selectedID {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(height: rowHeight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    bot.id == selectedID ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: height)
            }
            HStack {
                Button("Refresh") { Task { await account.reload() } }
                Spacer()
                Button("Sign out", action: account.signOut)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
}

struct AccountBotList: View {
    @Bindable var account: GrokAccount
    @Binding var selection: String?
    var onChoose: ((Bot) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch account.status {
            case .signedOut:
                signInPrompt("Sign in to load the bots on your Grok Bot account.")
            case .waitingForBrowser:
                Text("Finish signing in in the browser. This window will fill in your bots when that’s done.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel sign-in", action: account.cancelSignIn)
            case .loadingBots:
                ProgressView("Loading your bots…")
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                signInButton
            case .ready:
                if let label = account.accountLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if account.bots.isEmpty {
                    Text("This account has no bots yet.")
                        .foregroundStyle(.secondary)
                } else if selection == nil {
                    List(account.bots) { bot in
                        Button(bot.name) { onChoose?(bot) }
                            .buttonStyle(.plain)
                    }
                    .frame(minHeight: 180)
                } else {
                    List(account.bots, selection: $selection) { bot in
                        Text(bot.name).tag(bot.id)
                    }
                    .frame(minHeight: 160)
                }
                HStack {
                    Button("Refresh") { Task { await account.reload() } }
                    Spacer()
                    Button("Sign out", action: account.signOut)
                }
            }
        }
    }

    private func signInPrompt(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            signInButton
        }
    }

    private var signInButton: some View {
        Button("Sign in to Grok Bot") { account.signIn() }
    }
}

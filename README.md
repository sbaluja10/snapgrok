# Snapgrok

Snapgrok lives in the Mac menu bar. Chrome is in front, you press **⌥⇧G**, and the front tab shows up in a [Grok Bot](https://cursor.com): a screenshot of the window, and a short link that still opens that exact page. The message waits in the composer. You press Return.

There is a one-page version of the same idea you can click: [sbaluja10.github.io/snapgrok](https://sbaluja10.github.io/snapgrok/).

## What you need

- macOS 14 or later
- Google Chrome
- The Grok Bot app

## First run

1. Build the app and open `dist/Snapgrok.app`.
2. Click **Snapgrok** in the menu bar and sign in with the account you use for Grok Bot. The bots on that account fill the list.
3. Pick one. Snapgrok remembers it, so the next **⌥⇧G** goes straight to that bot. Click the menu bar when you want a different one. Right-click for Launch at Login and Quit.
4. Allow Snapgrok in two places, then quit it and open it again so the grants apply:
   - **System Settings → Privacy & Security → Screen & System Audio Recording**
   - **System Settings → Privacy & Security → Accessibility**

Screen Recording is the screenshot. Accessibility is how the picture and the link get pasted into Grok Bot. Until Accessibility is on, Snapgrok still opens the bot and the menu bar reads **Allow Accessibility**.

## The shortcut

**⌥⇧G** while Chrome is the front app.

Snapgrok reads the active tab’s title and full URL, captures that Chrome window, shortens the address, brings Grok Bot forward, and pastes the picture and the link. Sending stays with you.

**Snap Front Chrome Tab…** in the menu does the same capture when Chrome is open but not in front.

## The link

The short link comes from [is.gd](https://is.gd). Opening it redirects to the original page, query string included. What gets pasted is a real link: the short URL is the label, and the full URL is the destination. If is.gd doesn’t answer within a few seconds, Snapgrok pastes the full URL. The page address is the only thing sent there.

## What stays on your Mac

The sign-in is stored in the Keychain under the service `local.snapgrok`. The latest screenshot is `~/Library/Application Support/snapgrok/captures/latest.png`. The bot you picked last is an ordinary preference.

## Build

```bash
./scripts/build-app.sh
open dist/Snapgrok.app
```

That builds a release binary, wraps it as `dist/Snapgrok.app`, and signs it with your Apple Development certificate when one is installed. The signature is what lets Screen Recording and Accessibility survive the next rebuild. With no certificate the script signs ad hoc, and macOS treats every new build as a different app, so you allow it again.

```bash
swift test
```

Version 0.1.0. The hotkey is Chrome, for now.

# ClipStack — macOS clipboard manager

A lightweight menu-bar clipboard history app written in Swift (pure AppKit — builds with Command Line Tools alone, no Xcode needed). No dependencies.

## Features
- Records **text, rich text (RTF/HTML), images and Finder files** copied anywhere on the system
- Menu-bar popover with search, keyboard navigation (↑ ↓ ⏎ Esc, ⌫ to delete)
- **Preview pane** showing the full clip with character/word/line counts, image dimensions, formatted text
- **Smart types** — detects URLs, emails, phone numbers, colors, JSON, numbers and code; shows a badge and offers actions:
  open URL / compose email / call, pretty-print or minify JSON, hex ↔ rgb(), strip tracking params,
  trim, collapse to one line, UPPER/lower/Title case, dedupe or sort lines
- **⌘1–⌘9** to paste the Nth item instantly; **⇧⏎** to paste as plain text
- Global hotkey (default **⌘⇧V**), changeable in Preferences
- Pin items so they survive "Clear" and history trimming
- Auto-paste into the app you were using (optional; needs Accessibility permission)
- **Preferences window**: hotkey recorder, history size, polling rate, rich-text capture, auto-paste, launch at login
- **Screenshot manager**: new screenshots are captured automatically, OCR'd on-device (searchable, "Copy text"), shown in the
  notch with Copy / Text / Reveal / Trash, optionally moved into `~/Pictures/Screenshots/YYYY-MM/` and renamed by date + app.
  Pasting a screenshot gives the file to Finder/Slack and the image to editors; drag chips out of the notch as files.
- **Instant capture shortcuts** (⌃⇧3 / ⌃⇧4 / ⌃⇧5 by default, rebindable): ClipStack runs the capture itself, so the file
  and history entry appear immediately — no floating-thumbnail delay. Also in the menu-bar right-click menu.
- Filter bar: All / Text / Images / Screenshots / Files
- **Now Playing in the notch**: album art on the left, animated audio bars on the right while Spotify / Apple Music plays;
  hover for a player card with progress and prev / play / next.
- **Interactive notch** (Dynamic-Island style): sits over the MacBook notch, flashes what you just copied, expands on hover
  to show your last 6 clips as tappable chips (tap = paste), click to open full history, and accepts drag-and-drop of
  files/text/images straight into the clipboard. Macs without a notch get a small pill at the top of the screen.
- Right-click the menu-bar icon for a quick menu; left-click opens history
- De-duplicates repeated copies; skips passwords from password managers (`org.nspasteboard.ConcealedType`)
- History persisted to `~/Library/Application Support/ClipStack/`

## Requirements
macOS 13 Ventura or later, Xcode 15+ or Command Line Tools with Swift 5.9+.

## Build & run
```bash
chmod +x build-app.sh
./build-app.sh      # builds, quits any running copy, launches the new one
```
For development: `swift run` (menu-bar icon appears; "Launch at login" is only available from the .app bundle).

## Permissions
- **Auto-paste** sends a synthetic ⌘V, which requires *System Settings → Privacy & Security → Accessibility → ClipStack*. The app prompts the first time; there's also a button in Preferences. Turn auto-paste off if you'd rather it only copy to the clipboard.
- The global hotkey works without any permission.

## Layout
| File | Purpose |
|---|---|
| `ClipItem.swift` | Model (text/rich/image/files, pinned, timestamp) |
| `ClipStore.swift` | History, de-dup, trimming, JSON persistence |
| `ClipboardMonitor.swift` | Polls `NSPasteboard.changeCount`; captures files, text+RTF/HTML, images |
| `SmartType.swift` | Content-type detection and text transformations |
| `Paster.swift` | Writes to pasteboard (rich/plain/override), simulates ⌘V |
| `HotKey.swift` | Carbon global hotkey, re-registers on settings change |
| `Settings.swift` | UserDefaults-backed settings, launch-at-login, key names |
| `PreferencesWindow.swift` | Preferences window + hotkey recorder |
| `HistoryView.swift` | Popover UI: list, preview pane, actions, quick-pick |
| `ScreenshotWatcher.swift` | Spotlight watcher, organize/rename, Vision OCR |
| `NowPlaying.swift` | Spotify / Music polling via Apple Events, audio-bars view |
| `NotchWindow.swift` | Notch panel: shape, toast, hover-expand chips, drag & drop |
| `AppDelegate.swift` | Status item, popover, wiring |

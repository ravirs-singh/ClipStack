# ClipStack — Product Hunt listing

## Name
ClipStack

## Tagline (≤ 60 chars)
Clipboard, screenshots and a living notch for your Mac

Alternatives:
- Your MacBook notch, finally useful
- Clipboard history + OCR screenshots + a Dynamic Island for Mac

## Description (≤ 260 chars)
ClipStack keeps everything you copy, OCRs every screenshot, and turns the MacBook notch into a Dynamic-Island-style surface: Now Playing, Claude Code approvals, a file shelf, Pomodoro, calendar and weather. Free, open source, pure AppKit, no cloud.

## Topics
Mac, Productivity, Open Source, Developer Tools, Design Tools

## Links
- Website / GitHub: https://github.com/OWNER/ClipStack
- Download: https://github.com/OWNER/ClipStack/releases/latest
- Video: brag-output/brag.mp4 (upload to YouTube and paste the link; PH embeds YouTube)

## Pricing
Free

## Gallery (1270×760, in `launch/gallery/`)
1. The island — Home card
2. Clips tab: the clipboard in the notch
3. Full history window with one-click actions
4. Claude Code approval from the notch
5. Shelf
6. Prompter
7. Screenshot + OCR

Thumbnail: `launch/logo-240.png` (240×240). Hero video: YouTube link of the brag video.

## First comment (maker)
Hey Product Hunt 👋

I built ClipStack because three things annoyed me every day on my MacBook:

1. **I kept losing things I'd copied.** So ClipStack keeps everything: text, links, images, files. ⌘⇧V to search, ⌘1–9 to paste anything instantly. It knows what you copied, so JSON gets pretty-print, URLs lose their tracking junk, colors convert.
2. **Screenshots are where text goes to die.** Every capture is OCR'd on-device the moment it lands, so you can search it and copy the words out. Capture shortcuts fire instantly, no floating-thumbnail delay.
3. **The notch does nothing.** Now it unfolds into a Dynamic-Island-style surface: Now Playing (Spotify, Apple Music, YouTube Music), a file shelf you can drop things on, Pomodoro with a countdown ring, calendar and weather. And if you use Claude Code, permission requests show up in the notch and you approve them right there without switching windows.

It's free and MIT-licensed, pure AppKit, builds with just the Command Line Tools, and never talks to a server (the only network request is weather, and only if you turn it on).

One-line install:
`curl -fsSL https://raw.githubusercontent.com/OWNER/ClipStack/main/install.sh | bash`

Would love to hear what you'd put in the notch next.

## Launch checklist
- [ ] Create the new public GitHub repo and push (replace `OWNER` everywhere: `grep -rl OWNER --exclude-dir=.git . | xargs sed -i '' 's#OWNER#your-handle#g'`)
- [ ] Apple Developer ID: run `./release.sh 1.0.0`, upload the DMG as a GitHub Release `v1.0.0` (unsigned builds trigger Gatekeeper warnings and hurt conversion)
- [ ] Put `sha256` from release.sh into `Casks/clipstack.rb`; push it to a `homebrew-clipstack` tap repo
- [ ] Upload brag.mp4 to YouTube (unlisted is fine), use the vertical cut for X / Instagram / TikTok teasers
- [ ] Add 3–5 real screenshots from your own Mac to the gallery alongside the rendered ones
- [ ] Schedule for 12:01 AM PT on a Tuesday–Thursday; reply to every comment in the first 4 hours
- [ ] Hunter: launch it yourself; a hunter with followers no longer boosts ranking

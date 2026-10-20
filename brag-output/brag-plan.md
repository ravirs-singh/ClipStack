# ClipStack — brag plan

**What is it:** ClipStack is a free, open-source macOS clipboard manager that also turns the MacBook notch into a living Dynamic-Island-style surface and auto-manages screenshots.

**Who / what for:** Mac users who copy a lot (devs, designers, ops people). Never lose a copied thing again; paste anything from the last 200 with ⌘1–9; screenshots arrive instantly with their text recognized.

**What sets it apart:** The notch. Album art + audio bars while music plays (Spotify, Apple Music, YouTube Music in Chrome), hover for recent clips and player controls, drop files on it. Plus on-device OCR for screenshots and smart types (URL/JSON/color/code) with one-click actions.

**Most impressive claim:** "Your notch, alive." — a part of the screen Apple left blank now shows what's playing and what you copied.

**Visual hook:** the black notch growing wings with album art and bouncing audio bars.

**Real UI shown:** the History window (sidebar list with tinted icon tiles, capsule badges, preview card), the notch island (player card + RECENT chips), the screenshot drop-down (Copy · Text · Reveal · Trash). The app is native AppKit, so these are rebuilt in HTML/CSS from the app's own layout, colors and type rules (SF-style sizes, system tint colors, continuous corners). The real app icon (`Assets/icon-1024.png`) is used as-is.

**Tone:** `default` — punchy, playful, clean, with an Apple-keynote restraint. Dark stage, big Inter Display type, the icon's blue→indigo as the only accent.

**Share caption:** "Your Mac remembers one thing you copied. ClipStack remembers 200 — and puts your music in the notch."

**Format:** landscape 1920×1080, 30 fps, 20 s. No fictional data: all clip text is real-looking developer/ops snippets with no personal data; the song shown is a placeholder title.

## Storyboard (20.0 s)

| # | Time | Scene | On screen | Motion / sound |
|---|---|---|---|---|
| 1 | 0.0–3.3 | Hook | "You copy a couple hundred things a day." then "Your Mac remembers one." | Word-by-word rise; soft pad swell; tick on line 2 |
| 2 | 3.3–6.5 | Reveal | App icon springs in, "ClipStack" wordmark, tagline "Clipboard history, screenshots and a living notch. For macOS." | Icon spring + glow bloom; bass note + sparkle |
| 3 | 6.5–11.0 | History | History window rises; rows pop in one by one; "invoice" typed into search → list filters to 2 rows; ⌘2 key cap pulses; preview shows text. Caption: "Everything you've copied. Searchable. ⌘1–9 pastes." | Staggered pops with soft ticks; key clicks on typing |
| 4 | 11.0–15.2 | Notch | Top of a Mac screen with menu bar. Notch grows wings: album art + audio bars. Cursor hovers; island expands: player card (art, title, progress, ⏮⏯⏭) + RECENT chips. Captions: "Your notch, alive." → "Now Playing · recent clips · drop files on it." | Whoosh on expand, synced to the beat |
| 5 | 15.2–18.0 | Screenshot | Crosshair selection draws across a window; shutter flash; thumbnail flies into the island with Copy · Text · Reveal · Trash; OCR text lines slide in. Caption: "Screenshots land instantly — text included." | Shutter click + rising chime |
| 6 | 18.0–20.0 | Outro | Icon + "ClipStack" + "Free & open source" + "github.com/ravirs-singh/ClipStack" + "⌘⇧V" | Everything settles; music resolves to the tonic and fades |

Transitions dip through the dark background (old out, then new in) — no crossfading busy layouts.

## Sound

One synthesized piece in A minor, 112 BPM: warm pad chords (Am–F–C–G), a plucked arpeggio, soft kick + hat from scene 3 on, sidechained under. Effects are notes/noises in the same key and reverb: ticks (row pops, typing), a filtered whoosh (island expand), a shutter click + chime (screenshot). Mixed with effects ~10 dB under the music, gentle lowpass, 1.2 s fade at the end.

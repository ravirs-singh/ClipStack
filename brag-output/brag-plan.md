# ClipStack — brag plan

**What is it:** ClipStack is a free, open-source macOS clipboard manager that also turns the MacBook notch into a living Dynamic-Island-style surface and auto-manages screenshots.

**Who / what for:** Mac users who copy a lot (devs, designers, ops people). Never lose a copied thing again; paste anything from the last 200 with ⌘1–9; screenshots arrive instantly with their text recognized.

**What sets it apart:** The notch. Album art + audio bars while music plays (Spotify, Apple Music, YouTube Music in Chrome), hover for recent clips and player controls, drop files on it. Plus on-device OCR for screenshots and smart types (URL/JSON/color/code) with one-click actions.

**Most impressive claim:** "Your notch, alive." — a part of the screen Apple left blank now shows what's playing and what you copied.

**Visual hook:** the black notch growing wings with album art and bouncing audio bars.

**Real UI shown:** the History window (sidebar list with tinted icon tiles, capsule badges, preview card), the notch island (player card + RECENT chips), the screenshot drop-down (Copy · Text · Reveal · Trash). The app is native AppKit, so these are rebuilt in HTML/CSS from the app's own layout, colors and type rules (SF-style sizes, system tint colors, continuous corners). The real app icon (`Assets/icon-1024.png`) is used as-is.

**Tone:** `default` — punchy, playful, clean, with an Apple-keynote restraint. Dark stage, big Inter Display type, the icon's blue→indigo as the only accent.

**Share caption:** "Your Mac remembers one thing you copied. ClipStack remembers 200 — and puts your music in the notch."

**Format:** landscape 1920×1080 (`brag.mp4`) and a vertical 1080×1920 Reels/Shorts cut (`brag-vertical.mp4`), 30 fps, 25 s. No fictional data: all clip text is real-looking developer/ops snippets with no personal data; the song shown is a placeholder title.

## Storyboard (25.0 s)

| # | Time | Scene | On screen | Motion / sound |
|---|---|---|---|---|
| 1 | 0.0–3.3 | Hook | "You copy a couple hundred things a day." then "Your Mac remembers one." | Word-by-word rise; pad swell; tick on line 2 |
| 2 | 3.3–6.5 | Reveal | App icon springs in, "ClipStack", tagline | Icon spring + glow; bass note + sparkle |
| 3a | 6.5–10.0 | Hotkey → history | ⌘ ⇧ V key caps press; History window rises; six rows pop in (code, invoice text, URL, screenshot, JSON, files). Caption: "Everything you copy, kept. Text, links, images, files." | Key click; staggered ticks |
| 3b | 10.0–12.9 | Search + paste | "invoice" typed → list filters to 2; ⌘1 key cap pulses, row highlights. Caption: "Search it. ⌘1–⌘9 pastes it anywhere." | Key clicks; blip on ⌘1 |
| 3c | 12.9–16.0 | Smart actions | JSON row selected, "JSON" badge; Actions menu opens (Pretty-print, Minify, Trim, …); Pretty-print highlighted → preview reformats. Caption: "It knows what it copied. One-click actions." | Menu ticks; chime on reformat |
| 4 | 16.0–20.2 | Notch | Notch grows wings (album art + audio bars); cursor hovers; island expands with player card + RECENT chips. Captions: "Your notch, alive." → "Now Playing · recent clips · drop files on it." | Whooshes synced to beat |
| 5 | 20.2–23.0 | Screenshot | Crosshair selection; shutter; thumbnail flies into the island with Copy · Text · Reveal · Trash; recognized-text card. Caption: "Screenshots land instantly — text included." | Shutter + chime |
| 6 | 23.0–25.0 | Outro | Icon + "ClipStack" + "Free & open source" + GitHub URL + ⌘⇧V | Music resolves and fades |

Transitions dip through the dark background — no crossfading busy layouts. The vertical cut stacks the History window's list above its preview and zooms the Mac scenes around the notch.

## Sound

One synthesized piece in A minor, 112 BPM: pad chords looping Am–F–C–G, a plucked arpeggio from the reveal, soft kick + hat from the hotkey beat, ducked under. Effects are in key and in the same reverb: key clicks, ticks on pops, whooshes on the island, shutter + chime for the screenshot. Effects ~10 dB under the music, gentle lowpass, 1.4 s fade.

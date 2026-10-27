# ClipStack — brag plan (v2, the island)

**What is it:** ClipStack is a free, open-source macOS app that turns the MacBook notch into a Dynamic-Island-style command surface — clipboard history, AI-agent approvals, a file shelf, Pomodoro, Now Playing, calendar — and a full clipboard manager with instant screenshots + OCR behind it.

**Who / what for:** People who build with Claude Code and copy a lot. One hover shows what's playing, what the agent is doing, what's next; one click approves an agent command; files and clips live a hover away.

**What sets it apart:** the notch is the UI. Agent permission requests land in the notch and you answer from there. Clipboard history is deep (200 items, smart types, ⌘1–9). Free and open source.

**Most impressive claim:** "Claude Code asks for permission. You approve from the notch."

**Visual hook:** the black notch growing wings (album art + audio bars), then unfolding into the island with four glass cards.

**Real UI shown:** the island exactly as built — tab capsule (icon tabs, selected one expands into a labelled pill), Home cards (Now Playing with circle controls, Claude card with state dot and big session count, Weather, Up next with big time), the Agents permission card with Allow/Deny pills, the Clips two-card layout with chips, the Shelf, the Focus tab (big 25:00, Pomodoro/Timer pills, "Would end at", progress line, session dots), and the collapsed notch wings (art + bars, timer ring + countdown). Rebuilt in HTML/CSS from the AppKit layout code (same sizes, radii, colours). Real app icon used.

**Tone:** `default` — punchy, clean, keynote-ish. Dark stage; the island does the talking.

**Share caption:** "Your Mac's notch, finally useful: music, your Claude Code agent asking for permission, a shelf for files, a Pomodoro — and a 200-item clipboard behind it. ClipStack, free and open source."

**Format:** 1920×1080 + 1080×1920 vertical, 30 fps, 25 s. No real personal data; song, city, event and agent command are placeholders.

## Storyboard (25.0 s)

| # | Time | Scene | On screen | Sound |
|---|---|---|---|---|
| 1 | 0.0–3.0 | Hook | "Your notch has been doing nothing." → "Until now." | pad swell, tick |
| 2 | 3.0–5.6 | Reveal | Icon springs in · "ClipStack" · "Clipboard, screenshots and a living notch. Free, open source." | boom + sparkle |
| 3a | 5.6–10.5 | Island · Home | Mac top; notch grows wings (art + bars); cursor rests; island unfolds to Home: Now Playing, Claude (Running · 2), Weather (23°), Up next (16:00 Product review). Caption: "Hover the notch. Everything that matters, at a glance." | whoosh, chips ticks |
| 3b | 10.5–14.3 | Agents | Tab slides to Agents; orange card "clipstack wants to run Bash · npm run build" with Allow / Deny; cursor clicks Allow → card becomes "clipstack · Working". Caption: "Claude Code asks for permission. Approve from the notch." | tick, click, chime |
| 3c | 14.3–16.3 | Clips | Tab → Clips: "200 items kept · 39 copied today" + six chips. Caption: "Your clipboard, searchable. ⌘1–9 pastes." | ticks |
| 3d | 16.3–18.3 | Shelf | Tab → Shelf; a file flies onto the island; count 0→1, chip appears. Caption: "Drop files on the notch. Drag them out anywhere." | whoosh, pop |
| 3e | 18.3–21.4 | Focus | Tab → Focus: 25:00, Pomodoro pill, "Would end at", line + session dots; click play → island collapses; notch shows ring + 24:59 next to the album art. Caption: "Pomodoro, right in the notch." | click, morph whoosh |
| 4 | 21.6–25.0 | Outro | Icon + ClipStack · "Clipboard history · Screenshots + OCR · Agents · Shelf · Focus · Now Playing" · github.com/ravirs-singh/ClipStack · Free & open source | resolve, fade |

## Sound
Same synthesized A-minor piece at 112 BPM as v1, re-timed: pad chords, plucked arpeggio from the reveal, soft kick + hat from the island scene, effects in key (ticks for tab/chip pops, whoosh for the island morph, click for Allow, bell for approval and timer start). 1.4 s fade.

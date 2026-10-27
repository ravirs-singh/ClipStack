# ClipStack brag video — v3 (narrated, 78 s)

Landscape `brag.mp4` 1920×1080 and vertical `brag-vertical.mp4` 1080×1920, 30 fps, poster baked as frame 0.
Soundtrack: synthesized bed (A minor, 112 BPM: pad, plucked arpeggio, kick/hat) + keyed sound effects + AI voice-over
(edge-tts, en-US-AndrewMultilingualNeural), music ducks to ~38 % under speech.

| # | Scene | Time | Voice-over | On screen |
|---|---|---|---|---|
| 1 | Hook | 0:00–0:04 | "Your notch has been doing nothing." | Headline on black |
| 2 | Intro | 0:04–0:14 | Meet ClipStack: clipboard, screenshots, a living notch | Icon reveal, history window rises |
| 3 | Clips | 0:14–0:25 | Everything you copy is kept; ⌘⇧V, search, ⌘1–9 | ⌘⇧V, typing "invoice", ⌘1 paste |
| 4 | Smart | 0:25–0:33 | It knows what you copied, one-click actions | JSON action menu → pretty-printed |
| 5 | Shots | 0:33–0:40 | Screenshots land instantly, OCR'd on-device | ⌃⇧4 capture, flies into the notch, recognized text |
| 6 | Island | 0:40–0:50 | Hover the notch: Now Playing, agents, weather, up next | Wings grow, island unfolds, card spotlights |
| 7 | Agents | 0:50–1:00 | Claude Code asks for permission, approve from the notch | Orange request, Allow click, session goes green |
| 8 | Shelf | 1:00–1:07 | Drop files on the notch, drag them out anywhere | File flies into the Shelf |
| 9 | Focus | 1:07–1:12 | Pomodoro, right in the notch | Play, collapse to countdown ring |
| 10 | Outro | 1:12–1:18 | Free and open source | Logo, feature line, "Free & open source on GitHub" |

Source: `work/comp3.html` (timeline derived from `work/voice/durations.json`), `work/capture3.js`, `work/audio3.py`.
Rebuild: `node capture3.js && node capture3.js --vertical && python3 audio3.py`, then the ffmpeg lines in the session log.

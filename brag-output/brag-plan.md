# ClipStack brag video — v4 (notch-first, narrated, 87 s)

Landscape `brag.mp4` 1920×1080 and vertical `brag-vertical.mp4` 1080×1920, 30 fps, poster baked as frame 0.
The island is the stage from the intro to the Pomodoro: the clipboard is shown as the Clips tab of the notch, with the full
history window dropping down from it. Soundtrack: synthesized bed (A minor, 112 BPM) + keyed sound effects + AI voice-over
(edge-tts, en-US-AndrewMultilingualNeural), music ducks to ~38 % under speech.

| # | Scene | Time | Voice-over | On screen |
|---|---|---|---|---|
| 1 | Hook | 0:00–0:04 | "Your notch has been doing nothing." | Headline on black |
| 2 | Intro | 0:04–0:12 | Turns the MacBook notch into a living command surface | Icon reveal → notch wings grow → island unfolds |
| 3 | Home | 0:12–0:21 | What's playing, your agent, the weather, what's next | Card spotlights on the Home tab |
| 4 | Clips | 0:21–0:33 | The Clips tab is your clipboard; tap to paste, ⌘1–6 | Clips tab, chip tap, key pulse |
| 5 | Full history | 0:33–0:44 | ⌘⇧V, search, one-click actions | History window drops below the island, JSON → pretty |
| 6 | Agents | 0:44–0:54 | Claude Code asks for permission, approve from the notch | Orange request, Allow click, session goes green |
| 7 | Shelf | 0:54–1:01 | Drop files on the notch, drag them out anywhere | File flies into the Shelf |
| 8 | Prompter | 1:01–1:08 | The Prompter tab scrolls your script, right under the camera | Prompter tab, play, text rolls |
| 9 | Focus | 1:08–1:13 | Pomodoro, right in the notch | Play, collapse to the countdown ring |
| 10 | Screenshots | 1:13–1:20 | Screenshots land instantly, text recognized | ⌃⇧4 capture flies into the notch, OCR card |
| 11 | Outro | 1:20–1:27 | Free and open source | Logo, feature line |

Source: `work/comp4.html` (timeline from `work/voice/durations.json`), `work/capture4.js`, `work/audio4.py`, `work/voice/gen4.py`.
Rebuild: `node capture4.js && node capture4.js --vertical && python3 audio4.py`, then encode with ffmpeg (libx264 crf 18 + aac 192k).

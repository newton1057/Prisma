# Orb renderer

Draws the macOS orb frame by frame, without the app, through a scripted sequence of state changes. Use it to see transitions: knots, slits, flips and cross-fades show up on a contact sheet even when a few screenshots of the running app look fine.

```bash
tools/orb-renderer/render.sh <out-dir> [fps=30] [cycle|silent|interrupt]
python3 tools/orb-renderer/sheet.py <out-dir> <sheet.png> <fps> <event-seconds,...> [span] [step] [tile]
python3 tools/orb-renderer/diffs.py <out-dir> <fps> <event-seconds,...>
```

| Scenario | Sequence |
|---|---|
| `cycle` | Waiting, thinking at 1.0 s, voice at 3.6 s with a synthetic voice, waiting at 6.6 s. Events: `1.0,3.6,6.6`. |
| `silent` | The same without audio, so speech-driven motion does not hide cuts in `diffs.py`. |
| `interrupt` | Thinking at 0.5 s, voice at 1.0 s, waiting at 1.6 s, thinking at 2.0 s: every transition starts before the previous one ends. |

`render.sh` compiles `Harness.swift` with the app's current `app/Sources/Prisma/OverlayView.swift`, so it always renders the code in the working tree. It writes one PNG per frame and a `weights.csv` with the pose weights.

`diffs.py` prints, for each event, the peak frame-to-frame change and the largest change of that change. A spike against the motion before the event means a cut.

The native glass blur cannot be drawn offscreen, so the renderer uses a dark stand-in. Judge the glass itself, and the real frame rate, in the running app; see [Verification](../../docs/orb-and-sessions.md#8-verification).

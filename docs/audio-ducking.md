# Background audio ducking on macOS

Date: 2026-10-30
Status: implemented and verified on macOS 26.4 (Apple Silicon)
Original commit: `f1366c9`

This document describes macOS. Windows uses per-session attenuation; see the [Windows guide](windows.md).

## 1. Behavior

When Prisma starts speaking, it:

1. Smoothly lowers the Mac's output device volume to 35% by default, putting music, video, or calls in the background.
2. Compensates its own voice with gain and a peak limiter so it remains audible over the background.
3. Restores the previous volume with a short ramp when speech ends.

The Spanish-language interface offers these options under **Ajustes → Audio de fondo** (Settings → Background audio):

- Lower music and videos while Prisma speaks (enabled by default).
- Volume while speaking: 15%–70%, in 5% increments (35% by default).

## 2. Design

The available approaches were:

| Option | Outcome |
|---|---|
| Lower the output device volume using CoreAudio | Simple and works with apps and players, but affects the entire system. **Selected.** |
| Capture and remix other apps' audio using CoreAudio taps (macOS 14.4+) | Requires audio capture permission and a graph per process; left for future investigation. |
| Mute individual apps through private APIs | Fragile and unsuitable for distribution; rejected. |

Because lowering the global volume also lowers Prisma's voice, the app compensates it:

```text
compensation (dB) = 20 · log10(base_volume / ducked_volume)
```

Compensation is capped at **+12 dB** to avoid overdriving the engine or limiter. Gain is applied before Apple's `PeakLimiter` so the voice can be raised without distortion. `SpeechSession` uses `AVAudioEngine` and `AVAudioUnitEffect` (PeakLimiter) instead of `AVAudioPlayer`, which cannot provide the required positive gain and peak limiting.

## 3. Flow

```text
POST /speak
   │
   ├─ Synthesize first chunk (Edge / Piper)
   │
   ├─ SpeechSession, just before first playback:
   │     duckBoost()  ──►  SpeechController.startDuckingForVoice()
   │                          ├─ duckAudio disabled? → restore and return 0
   │                          └─ SystemAudioDucker.duck(to: duckLevel)
   │                                ├─ read default output device volume
   │                                ├─ calculate target and compensation
   │                                ├─ ramp down (0.35 s)
   │                                └─ schedule 10-minute watchdog
   │
   ├─ 0.32-second pre-roll when compensation is active
   │
   ├─ AVAudioEngine playback
   │     └─ preGain (+dB) → PeakLimiter → mainMixer → output
   │
   ├─ Each chunk: keepAlive() refreshes the watchdog
   │
   └─ Finish, /stop, normal exit, or SIGTERM
         └─ restore() / restoreImmediately()
               └─ ramp up to previous volume (0.5 s)
```

## 4. Components

| File | Responsibility |
|---|---|
| `app/Sources/Prisma/SystemAudioDucker.swift` | Reads and writes device volume via CoreAudio, calculates compensation, ramps, respects manual changes, and runs the watchdog. |
| `app/Sources/Prisma/SpeechController.swift` | Starts ducking before playback, applies pre-roll, passes gain to the limiter, and restores on finish, stop, and shutdown. |
| `app/Sources/Prisma/SettingsStore.swift` | Persists `duckAudio` (Bool, default `true`) and `duckLevel` (Double, default `0.35`). |
| `app/Sources/Prisma/SettingsView.swift` | Provides the background-audio toggle, slider, and explanatory text. |
| `app/Sources/Prisma/AppDelegate.swift` | Calls `SpeechController.shutdown()` on application termination and `SIGTERM`. |

## 5. Parameters

| Parameter | Value | Location |
|---|---|---|
| Default ducking level | 35% | `SettingsStore` |
| Setting range | 15%–70%, 5% steps | `SettingsView` |
| Internal factor limit | 10%–85% | `SystemAudioDucker.duck` |
| Minimum volume for ducking | > 0.02 | `SystemAudioDucker.duck` |
| Maximum compensation | +12 dB | `SystemAudioDucker` and `applyLimiterGain` |
| Ramp down | 0.35 s | `SystemAudioDucker` |
| Ramp up | 0.5 s | `SystemAudioDucker` |
| Pre-roll before first word | 0.32 s | `SpeechController` |
| Safety watchdog | 600 s, refreshed per chunk | `SystemAudioDucker` |
| Apple fallback ducking | `max(0.65, duckLevel)` | `SpeechController.speakWithApple` |

The Apple voice uses gentler ducking because `AVSpeechSynthesizer` cannot receive gain compensation; otherwise the fallback could become hard to hear.

## 6. Edge cases

- **Very low or muted volume:** if the current level is ≤ 0.02, ducking and compensation are skipped.
- **Device without volume control:** for some HDMI, aggregate, or virtual devices, `AudioObjectIsPropertySettable` returns false and ducking is skipped.
- **Manual volume change during speech:** restoration respects the user's adjustment instead of forcing the previous level.
- **Repeated ducking:** the original base volume is retained and factors do not accumulate.
- **`/stop`:** initiates immediate restoration with a ramp.
- **Normal app exit:** `applicationWillTerminate` restores the volume.
- **`SIGTERM`:** a dedicated handler restores the volume before exit; `install.sh` uses this signal with `pkill`.
- **Long messages:** each chunk refreshes the watchdog so it does not restore volume mid-sentence.
- **Playback failure:** `finish()` restores the volume even if playback never starts.

## 7. Manual verification

Play music or video on the Mac and run:

```bash
~/Desktop/Prisma/test.sh "This is a background audio ducking test while Prisma speaks."
```

Expected: background audio drops before the first word, the voice remains clear, and volume smoothly returns to its previous level after speech.

Restoration checks:

```bash
# Restore with /stop; use the port reported in runtime.json.
curl -sS -X POST "http://127.0.0.1:8788/stop" -H "X-Prisma-Token: $(jq -r .token "$HOME/Library/Application Support/Prisma/runtime.json")"

# Normal exit
osascript -e 'quit app "Prisma"'

# SIGTERM, as used by install.sh
pkill -TERM -f "Prisma.app/Contents/MacOS/Prisma"
```

To observe device volume during the test, repeatedly run `osascript -e 'output volume of (get volume settings)'` or use a CoreAudio meter.

### Verification evidence

| Test | Result |
|---|---|
| Base volume 1.0 | 1.0 → 0.35 → 1.0 |
| Base volume 0.5 | 0.5 → 0.175 → 0.5 |
| `/stop` during speech | Volume restored |
| Normal app exit | Volume restored |
| `SIGTERM` | Volume restored |
| Setting disabled | Volume unchanged |
| Voice compensation (+9 dB) | RMS −20.2 → −13.2 dBFS; peak limited to 0.0 dBFS |
| Orb while speaking | Visible, unclipped, with animation driven by the RMS tap |

## 8. Known limitations

- **Global effect:** notifications, alarms, and calls are attenuated as well as music.
- **Default output device only:** changing devices mid-sentence does not duck the new device; restoration targets the original device.
- **`SIGKILL` or a process crash:** there is no opportunity to restore; the 10-minute watchdog runs only while the process is alive.
- **Apple voice has no gain compensation:** its minimum ducking level is 65%.
- **No automated ramp or restoration tests:** verification is manual, as described above.

## 9. Future improvements

1. Evaluate per-app CoreAudio process taps (macOS 14.4+) to attenuate content apps while leaving notifications and calls alone; this requires capture permission and a mixing graph.
2. Observe `kAudioHardwarePropertyDefaultOutputDevice` and transfer ducking when the output changes.
3. Add unit tests for `restoreTarget` and an integration test with a reference tone.
4. Expose orb meter sensitivity if RMS proves too conservative for quiet voices.
5. Make ramp durations configurable for users who prefer slower transitions.

## 10. History

**2026-10-30:** initial implementation of `SystemAudioDucker`, `AVAudioEngine` and PeakLimiter integration, pre-roll, user settings, watchdog, and restoration on `/stop`, exit, and `SIGTERM`. Manually verified and published on `main` in `f1366c9`.

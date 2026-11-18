# Performance follow-up — 2026-11-17

The reference already includes Claude's uncommitted idle-rest and in-process monitoring fixes. This comparison does not attribute their earlier 200% CPU reduction to the follow-up work. The initial source snapshot, installed-app ZIP and binary diff are in `tmp/performance-2026-11-17/`.

## Measured application results

Two alternating before/after pairs used the same 11 detected session orbs. Each scenario warmed up for at least 13 seconds, then sampled for 15 seconds. Values below are the median of each run's median. CPU is percent of one core; memory is kernel physical footprint in decimal MB.

| Workload | CPU before | CPU after | RAM before | RAM after |
|---|---:|---:|---:|---:|
| 1 thinking | 10.98% | 9.21% | 123.0 MB | 111.5 MB |
| 3 thinking | 14.03% | 13.92% | 131.6 MB | 111.1 MB |
| 6 thinking | 19.57% | 19.60% | 144.4 MB | 114.8 MB |
| Returned to rest | 0.51% | 0.28% | 64.4 MB | 56.1 MB |

The clearest measured gains are resting CPU and active RAM. One thinking orb used about 16% less CPU. Three/six thinking orbs do not show a material CPU improvement: their results are within the observed run-to-run spread. The final renderer evaluated the active timelines at about 60 Hz in both runs; the first reference run varied from about 57 to 60 Hz under host load. These are in-app timeline counts, not GPU presentation measurements. RAM allocations also varied materially between fresh processes; this table describes the observed host workload, not fixed resource limits. Full raw samples, including frame counts and orb counts, are in `tmp/performance-2026-11-17/repeated-final/`. Earlier exploratory runs with 12 orbs are retained separately and are not mixed into this table.

| Bundle measurement | Before | After | Change |
|---|---:|---:|---:|
| Logical app bytes | 1,989,394 | 2,096,338 | +106,944 bytes |
| Executable bytes | 1,931,920 | 2,038,864 | +106,944 bytes |

The app grew by about 107 KB (5.4%). Voice models and the Python runtime are outside the bundle and are excluded. Benchmarks, source snapshots, counters and diagnostic tools are not shipped in the app. These benchmark builds used version 1.0.6/build 6. The production changes are included in 1.0.7/build 7.

## Implemented changes

- Renderer: static sampling coordinates and voice tapers; loop-only bands reuse identical sampled colours within each canvas; absent pose colour work is skipped; a uniformly black interior mask is omitted. The seven bands, 72 outline intervals, blend modes, frame intervals and rest/wake timings remain unchanged. An exploratory shared-geometry capture was removed after its whole-app CPU results failed to justify it.
- Metadata: serial utility queue, coalesced requests, cached Codex index checks, Claude transcript paths/file stamps, expiring negative results, array-content prompts and appended custom titles. Session generations reject stale results after handover/close.
- Transcript monitoring: bounded reads on a separate utility queue; turn generations and offsets reject obsolete callbacks.
- Hover: coalesced pointer events, cached row bounds, old/new orb updates only, and an 80 ms timer only while the pointer is near a moving row. Newly shown orbs refresh the bounds immediately.
- Rendering availability: independent display/system/session/lock flags pause timelines, stop glides and process polling, then reset the motion timestamp and reconcile immediately on resume. Observers are installed before an inactive launch notification can arrive.
- Process monitoring: native argv is grouped once by executable; detectors share typed records; the 2 s timer has 150 ms leeway; existing Codex orbs no longer resolve metadata each cycle. The interval still supports prompt window-close detection.

Workspace sleep/session events use the public [NSWorkspace session notification API](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification). Explicit screen lock/unlock also observes the undocumented loginwindow distributed notifications, independently of display wake; the same names are used in the [MacAdmins Nudge implementation](https://github.com/macadmins/nudge/blob/main/Nudge/UI/Main.swift). Native checks exercise the lock handler directly rather than broadcasting fake system-wide lock notifications.

## Verification

- `bash tools/performance/check.sh`: motion, window detection, live native-process/ps equivalence, typed snapshots, metadata/transcript cache, agent connections, 66 Python tests, OpenCode flow and seven Swift package tests passed.
- Final motion/suspension tests and release builds passed after the renderer revision.
- Offline cycle/interruption/rest comparison: 157 selected 60 Hz frames are identical pixel-for-pixel; contact sheets were visually inspected. Native NSVisualEffectView is unchanged; the offline renderer uses its documented blur stand-in.
- Native test-copy checks: hover, handover, metadata invalidation, close and nested display/system/session suspension/resume passed. Explicit lock checks also passed in the final native check copy; a display wake did not override the independent locked state.
- In a simulated display-suspended stage, six thinking sessions stopped producing timeline frames; an earlier integrated build measured about 0.03% CPU and 81.9 MB. This is a simulated notification-state check, not a physical lock/sleep test on the user's Mac.

## Long-running verification

The first follow-up build used for the long-running observation is installed locally (`86084b2f1c92a46fc3063175ef66201c955332539aa21c5bf0014153774f2d6e`). A silent thinking/interrupt/session-end API smoke test passed.

The 24-hour stability result is pending. The independent observer started at 2026-11-17T19:22:35.252783+00:00 and is scheduled to finish at 2026-11-18T19:22:35.252783+00:00. At release preparation it had 539 samples over about 9.0 hours from one process. The first two heap snapshots had 416 and 213 live dispatch sources. The observer is independent of the tool session. Its job metadata is in `tmp/performance-2026-11-17/observation-job.json`; measurements are in `soak-24h.jsonl` in that directory. `tools/performance/record.py` records CPU/RAM and bundle size every 60 s, follows PID changes, and optionally samples live dispatch-source objects every six hours. It creates no orbs and sends no voice requests. A started log does not establish stability. Compare dispatch-source counts under similar activity; heap objects are not necessarily pending timers.

See [performance tools](../tools/performance/README.md) for reproduction commands and [aggregate measurements](performance-2026-11-17.json) for the per-run medians.

## Smaller orb windows

The next macOS build keeps the orb and badge on their original SwiftUI canvas inside a smaller native panel. The bottom placement went from 460 × 360 to 300 × 220 points, a 60.1% reduction in window area. Switching placement reanchors the panel around the orb before starting the slide. Hit testing uses the same origin correction as the hosted drawing.

The comparison used two alternating pairs with the same 13 sessions and the bottom placement. Each stage warmed up for 13 seconds and sampled for 15 seconds. The table reports the median of the two run medians. CPU denotes percent of one core. RAM is the physical footprint in decimal MB.

| Workload | CPU before | CPU after | RAM before | RAM after |
|---|---:|---:|---:|---:|
| 1 thinking | 7.82% | 7.52% | 110.0 MB | 107.3 MB |
| 6 thinking | 15.84% | 15.40% | 111.2 MB | 112.9 MB |
| Returned to rest | 0.31% | 0.31% | 54.5 MB | 52.6 MB |

Both runs showed a small CPU decrease with six thinking orbs and a small RAM increase. The other observed changes were within the spread across runs. Active timelines evaluated at about 60 Hz in all four runs. Raw samples are in `tmp/performance-panel/repeated/`.

The signed bundle grew from 2,096,338 to 2,096,690 bytes. The candidate is built at `app/Prisma.app`. The preceding installed build continues gathering its uninterrupted 24-hour log; the candidate used separate runtime directories for measurement.

The offline tests checked 300 visible frames at 2× across six placements and included the hover badge, speaking and entry/exit. They use the offline blur stand-in. A contact sheet is in `tmp/performance-panel/visual/sheet.png`.

Native checks confirmed the panel dimensions, hit target and initial glide position in all six placements. The change preserves the previous display as the glide reference when resizing temporarily overlaps another monitor. The release bundle signature and the full automated check suite passed.

## Static orb layers and earlier rest

The shadow, theme-coloured aura, side reflections and rim now have their own equatable views. The light still animates the beam and aura opacity. Braking starts 3 seconds after the orb becomes idle, down from 8 seconds. The same 2.6-second brake brings the light to rest in about 5.6 seconds.

Two alternating pairs used the same 13 sessions and the same six thinking orbs. Steady samples follow 13 seconds of warm-up. Post-activity samples start as the six orbs return to idle. CPU percent uses one core as 100%, RAM is physical footprint in decimal MB, and WindowServer includes the whole desktop.

| Metric | Before | After |
|---|---:|---:|
| Prisma CPU, six thinking | 14.40% | 14.49% |
| WindowServer CPU, six thinking | 36.30% | 36.82% |
| Prisma RAM, six thinking | 189.0 MB | 187.7 MB |
| Active timeline evaluations per second | 60 | 60 |
| Prisma CPU time in the first 15 s after activity | 1.34 s | 0.82 s |
| WindowServer median CPU in that interval | 31.31% | 27.86% |
| Prisma median RAM in that interval | 199.2 MB | 94.9 MB |
| Bundle | 2,096,690 bytes | 2,125,074 bytes |

Prisma used 39% less CPU time after activity and evaluated 43% fewer frames in that interval. Both builds converged to similar RAM at rest (about 96 and 94 MB at the end of the stage). The difference in the 15-second median measures the faster return to rest. Steady animation CPU remained essentially level.

### Layer and window diagnostics

Each diagnostic used a single isolated run bracketed by two runs with full rendering. Turning off a layer changes the image and serves only to identify costs. The shared window prototype moved the existing hosted views into one visible panel in the stationary scenario on one monitor. It did not exercise shared-window interaction or teardown of the hidden controller panels.

| Six thinking orbs | Visible panels | Prisma CPU | WindowServer CPU | Prisma RAM |
|---|---:|---:|---:|---:|
| Full rendering | 13 | 14.58% | 35.52% | 189.3 MB |
| No decorative layers | 13 | 14.24% | 34.80% | 150.8 MB |
| No animated beam | 13 | 3.54% | 32.75% | 62.1 MB |
| Shared native window | 1 | 14.65% | 38.80% | 190.3 MB |

The animated beam had the largest observed CPU and RAM cost. The shared window prototype gave no saving in this scenario, so the release build keeps one panel per orb. Raw results and the prototype are in `tmp/performance-layers/`.

The static-layer comparison produced 157 identical offline frames. The new rest sheet was reviewed separately. The release build is available at `app/Prisma.app`. The earlier installed build continues its 24-hour recording.

## Lower-cadence experiment

Two alternating pairs tested a lower target cadence only during steady thinking, using 13 sessions with six thinking orbs. Timeline evaluations fell from 47.3 to 36.0 per second. CPU fell from 19.42% to 17.63%, and physical footprint went from 189.2 to 189.8 MB. This experiment trades smoothness for CPU and is outside 1.0.7.

## Prisma 1.0.7 packages

The same GitHub release carries the macOS and Windows installers at version 1.0.7/build 7. The performance changes and benchmarks cover macOS. See the [release downloads](https://github.com/newton1057/Prisma/releases/tag/v1.0.7) and [package hashes and size](performance-2026-11-17.json).

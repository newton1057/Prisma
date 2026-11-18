# Performance checks

These tools measure macOS Prisma without adding diagnostics to the shipping
binary. Build and measurement outputs belong in `tmp/` (gitignored).

## Native application comparison

`prepare.py SOURCE DESTINATION` makes a source snapshot, changes its entry
point, exposes AppDelegate internals inside that copy only, counts timeline
frames, disables the updater, and builds a separate app. Preference writes
are discarded. The native glass, windows, animation and session monitors run
normally. Set `PRISMA_APP_SUPPORT` to a unique directory for every run; never
use the real runtime for these copies.

The harness measures its own cumulative process CPU with `getrusage` and
physical footprint with `task_info`. It emits one sample per second after
warm-up. CPU percent uses one core as 100%; memory and bundle sizes in the
report use decimal MB. The frame counter counts timeline body evaluations,
not screen-recording frames or GPU presentation fences.

```bash
python3 tools/performance/prepare.py /path/to/before tmp/bench-before
python3 tools/performance/prepare.py . tmp/bench-after
python3 tools/performance/repeat.py \
  tmp/bench-before/app/Prisma.app/Contents/MacOS/Prisma \
  tmp/bench-after/app/Prisma.app/Contents/MacOS/Prisma \
  tmp/comparison --repeats 3 --stages thinking-6,settle-6 --window-server
```

Repeated runs alternate before/after order, wait at least 13 s for each state,
then sample for 15 s. The `settle-6` stage samples immediately after the
preceding `thinking-6` stage, including the transition to rest. It records
CPU time and total timeline updates across the first 15 s. With
`--window-server`, each run has a companion file with cumulative WindowServer
CPU and resident bytes. WindowServer measurements include all visible apps.
Keep the pointer outside the orb row. Other agents and
processes can affect compositor load and CPU frequency: inspect the per-run
spread, orb count and frame rates before attributing a small change to code.
The standalone synthetic speaking state exercises voice graphics without
audio generation or playback; it is not an end-to-end speech benchmark.
Display suspension is simulated inside copies supporting it, so the user's
screen is never locked or put to sleep by the harness.

## Visual comparison and tests

```bash
bash tools/performance/check.sh
python3 tools/performance/compare_frames.py /path/to/before . tmp/visual-comparison
```

The image comparison simulates every 60 Hz motion step and rasterizes selected
timestamps around cycle, interruption, rest and wake boundaries. Review the
three `after-*.png` contact sheets as well as `comparison.json`. Native glass
uses the renderer's stand-in; the live comparison retains NSVisualEffectView.
For versions with different rest timing, use `--scenarios cycle,interrupt`
and render the rest contact sheets separately.
The native comparison measures the entire application; isolated arithmetic
benchmarks must not be presented as application-wide CPU savings.

The viewport check in `check.sh` samples entrance, hover, thinking, speaking
and exit for all six placements at 2×. It fails if the window bounds exclude
pixels above one 8-bit alpha step. With `PRISMA_BENCHMARK_VALIDATE_ONLY=1`, the
instrumented app also checks the native window size, hosting coordinates and
pointer hit targets as the placement changes.

## Long-running observation

```bash
python3 tools/performance/record.py --output tmp/soak.jsonl \
  --duration 86400 --interval 60 --heap-every 21600
```

This records the installed app using the PID from its runtime file, follows
restarts, and never sends voice requests or creates orbs. CPU comes from
`proc_pid_rusage` cumulative nanoseconds; RAM is physical footprint. It records
logical bundle bytes, excluding the external voice models and Python runtime.
The optional heap snapshots count live `dispatch_source_t` objects, not queued
callbacks; counts must be compared under comparable activity. Heap snapshots
can pause the target briefly, so they are disabled unless explicitly requested
with `--heap-every`. A started log is not a completed 24-hour stability check.

#!/usr/bin/env python3
"""Low-frequency macOS measurements of the installed app, including restarts.

No voice requests, agent sessions, configuration changes or credentials are
written. CPU is per-core percent; memory is the kernel physical footprint.
"""
import argparse
import ctypes
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import time


class Usage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in [
        'user', 'system', 'package_wakeups', 'interrupt_wakeups', 'pageins', 'wired', 'resident',
        'footprint', 'start', 'exit', 'child_user', 'child_system', 'child_package_wakeups',
        'child_interrupt_wakeups', 'child_pageins', 'child_elapsed', 'disk_read', 'disk_written']]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime', type=Path, default=Path.home() / 'Library/Application Support/Prisma/runtime.json')
    p.add_argument('--app', type=Path, default=Path.home() / 'Applications/Prisma.app')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--duration', type=float, default=86400)
    p.add_argument('--interval', type=float, default=60)
    p.add_argument('--heap-every', type=float, default=0,
                   help='Optional intrusive heap snapshots, seconds; disabled by default.')
    p.add_argument('--once', action='store_true')
    a = p.parse_args()
    if a.interval <= 0 or a.duration < 0 or a.heap_every < 0:
        p.error('Intervals must be positive and duration nonnegative.')
    lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    lib.proc_pid_rusage.restype = ctypes.c_int
    a.output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    previous = None
    next_heap = start
    with a.output.open('a', buffering=1) as output:
        while True:
            now = time.monotonic()
            row = {'timestamp': datetime.now(timezone.utc).isoformat(), 'elapsed_seconds': now - start}
            try:
                pid = int(json.loads(a.runtime.read_text())['pid'])
                usage = Usage()
                if lib.proc_pid_rusage(pid, 2, ctypes.byref(usage)) != 0:
                    raise OSError(ctypes.get_errno(), 'proc_pid_rusage failed')
                cpu = usage.user + usage.system
                identity = (pid, usage.start)
                row.update(pid=pid, footprint_bytes=usage.footprint, resident_bytes=usage.resident,
                           app_bytes=sum(f.stat().st_size for f in a.app.rglob('*') if f.is_file() and not f.is_symlink()))
                if previous is not None and previous[0] == identity:
                    row['cpu_percent'] = (cpu - previous[2]) / 1e9 / (now - previous[1]) * 100
                    row['wakeups_per_second'] = (usage.interrupt_wakeups - previous[3]) / (now - previous[1])
                previous = (identity, now, cpu, usage.interrupt_wakeups)
                if a.heap_every and now >= next_heap:
                    heap = subprocess.run(['heap', str(pid)], capture_output=True, text=True, timeout=30)
                    match = re.search(r'^\s*(\d+)\s+\d+\s+[\d.]+\s+dispatch_source_t\s', heap.stdout, re.M)
                    if match: row['dispatch_source_objects'] = int(match.group(1))
                    next_heap = now + a.heap_every
            except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
                row['error'] = str(error)
                previous = None
            output.write(json.dumps(row) + '\n')
            if a.once or time.monotonic() - start >= a.duration: break
            time.sleep(min(a.interval, max(0, start + a.duration - time.monotonic())))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Alternate fixed-load native test copies; keep each run's raw samples."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def window_server_pid():
    for line in subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines():
        fields = line.split(None, 1)
        if len(fields) == 2 and fields[1].rsplit('/', 1)[-1] == 'WindowServer':
            return fields[0]
    raise RuntimeError('WindowServer PID not found')


def window_server_sample(pid):
    start = time.time()
    result = subprocess.check_output(['/bin/ps', '-p', pid, '-o', 'time=,rss='], text=True).split()
    end = time.time()
    cpu = 0.0
    for part in result[0].split(':'):
        cpu = cpu * 60 + float(part)
    return {'unix_time': (start + end) / 2, 'cpu_seconds': cpu, 'rss_bytes': int(result[1]) * 1024}

p = argparse.ArgumentParser()
p.add_argument('before', type=Path)
p.add_argument('after', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--repeats', type=int, default=3)
p.add_argument('--stages', default='thinking-6,returned-idle')
p.add_argument('--window-server', action='store_true', help='Record shared WindowServer usage alongside each run.')
a = p.parse_args()
stages = set(a.stages.split(','))
if 'settle-6' in stages and 'thinking-6' not in stages:
    p.error('settle-6 requires thinking-6 so there are six active orbs to settle')
a.output.mkdir(parents=True, exist_ok=True)
window_server = window_server_pid() if a.window_server else None
for repeat in range(a.repeats):
    # Reverse each pair to reduce systematic warm-up and thermal bias.
    pair = [('before', a.before), ('after', a.after)]
    if repeat % 2: pair.reverse()
    for label, binary in pair:
        result = a.output / f'{label}-{repeat + 1}.json'
        env = dict(os.environ, PRISMA_APP_SUPPORT=str((a.output / f'runtime-{label}-{repeat + 1}').resolve()),
                   PRISMA_BENCHMARK_OUTPUT=str(result.resolve()), PRISMA_BENCHMARK_STAGES=a.stages)
        command = [str(binary.resolve()), '-position', 'bottom', '-targetDisplay', 'active', '-restIdleOrbs', 'YES']
        if window_server:
            samples = [window_server_sample(window_server)]
            with subprocess.Popen(command, env=env) as app:
                while True:
                    try:
                        status = app.wait(timeout=1)
                        break
                    except subprocess.TimeoutExpired:
                        samples.append(window_server_sample(window_server))
                if status:
                    raise subprocess.CalledProcessError(status, command)
            result.with_suffix('.window-server.json').write_text(json.dumps(samples, indent=2) + '\n')
        else:
            subprocess.run(command, env=env, check=True)
        rows = json.loads(result.read_text())
        print(f'Finished {label} run {repeat + 1}: {len(rows)} samples', flush=True)

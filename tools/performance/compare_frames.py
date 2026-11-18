#!/usr/bin/env python3
"""Render identical motion at selected timestamps and compare pixel output."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

from PIL import Image, ImageChops, ImageStat

p = argparse.ArgumentParser()
p.add_argument('before', type=Path)
p.add_argument('after', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--scenarios', default='cycle,interrupt,rest')
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
a.output.mkdir(parents=True, exist_ok=True)
scenarios = a.scenarios.split(',')
events_by_scenario = {'cycle': '1,3.6,6.6', 'interrupt': '0.5,1,1.6,2'}
if 'rest' in scenarios:
    def rest_times(source):
        text = (source / 'app/Sources/Prisma/OverlayView.swift').read_text()
        delay = float(re.search(r'static let restDelay: TimeInterval = ([\d.]+)', text)[1])
        braking = float(re.search(r'static let settleDuration: TimeInterval = ([\d.]+)', text)[1])
        stop = delay + braking - 1.5
        hover, leave = stop + 1.4, stop + 2.9
        return [delay - 1.5, stop, hover, leave, leave + delay + braking, leave + delay + braking + 0.9]

    times = rest_times(a.before)
    if times != rest_times(a.after):
        p.error('Rest timings differ. Compare unchanged scenes with --scenarios cycle,interrupt.')
    events_by_scenario['rest'] = ','.join(f'{t:g}' for t in times)
for label, source in [('before', a.before), ('after', a.after)]:
    build = a.output / label
    build.mkdir(exist_ok=True)
    overlay = (source / 'app/Sources/Prisma/OverlayView.swift').read_text()
    (build / 'OverlayView.swift').write_text(overlay.replace('VisualEffectBlur(', 'HarnessBlur('))
    harness = (repo / 'tools/orb-renderer/Harness.swift').read_text()
    # Simulate every 60 Hz tick, but rasterize the timestamps used by the sheet
    # and several additional samples near the rest/wake boundaries.
    harness = harness.replace('            guard let image = renderFrame', '''            _ = model.frame(at: virtualNow)
            let interesting: [Double] = scenario == "rest"
                ? [REST_EVENTS]
                : (scenario == "interrupt" ? [0.5, 1, 1.6, 2] : [1, 3.6, 6.6])
            guard interesting.contains(where: { t >= $0 - 0.1 && t <= $0 + 1.3 }), f % 6 == 0 else { continue }
            guard let image = renderFrame'''.replace('REST_EVENTS', events_by_scenario.get('rest', '')))
    (build / 'Harness.swift').write_text(harness)
    subprocess.run(['swiftc', '-O', '-swift-version', '5', '-module-cache-path', str(a.output / '.module-cache'),
                    '-parse-as-library', str(build / 'Harness.swift'), str(build / 'OverlayView.swift'),
                    str(repo / 'tools/orb-renderer/StandIn.swift'),
                    '-o', str(build / 'render')], check=True)
for scenario in scenarios:
    events = events_by_scenario[scenario]
    for label in ['before', 'after']:
        build = a.output / label
        subprocess.run([str(build / 'render'), str(build / scenario), '60', scenario], check=True)
        subprocess.run([sys.executable, str(repo / 'tools/orb-renderer/sheet.py'), str(build / scenario),
                        str(a.output / f'{label}-{scenario}.png'), '60', events, '1.3', '6', '100'], check=True)
results = {}
for scenario in scenarios:
    diffs = []
    maximum = 0
    for before in (a.output / 'before' / scenario).glob('f*.png'):
        after = a.output / 'after' / scenario / before.name
        difference = ImageChops.difference(Image.open(before).convert('RGB'), Image.open(after).convert('RGB'))
        diffs.append(sum(ImageStat.Stat(difference).mean) / 3)
        maximum = max(maximum, max(channel[1] for channel in difference.getextrema()))
    results[scenario] = {'frames': len(diffs), 'mean_absolute_channel_difference_0_255': sum(diffs) / len(diffs),
                         'maximum_channel_difference_0_255': maximum}
(a.output / 'comparison.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))

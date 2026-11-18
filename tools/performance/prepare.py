#!/usr/bin/env python3
"""Build an instrumented test copy without changing the shipping sources."""
import argparse
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser()
p.add_argument('source', type=Path)
p.add_argument('destination', type=Path)
a = p.parse_args()
root = a.source.resolve()
out = a.destination.resolve()
if out.exists():
    raise SystemExit(f'Destination already exists: {out}')
for name in ['app/Sources', 'app/Tests', 'app/Package.swift', 'app/Info.plist', 'app/build.sh',
             'plugin', '.agents', '.claude-plugin']:
    src, dst = root / name, out / name
    if src.is_dir():
        shutil.copytree(src, dst)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
source = out / 'app/Sources/Prisma'
delegate = source / 'AppDelegate.swift'
text = delegate.read_text().replace('private ', '')
text = text.replace('NSEvent.mouseLocation', 'benchmarkPointer()')
text = text.replace('Task { [weak self] in await self?.updater.watch() }',
                    '// Updater disabled in the isolated performance copy.')
delegate.write_text(text)
settings = source / 'SettingsStore.swift'
settings.write_text(settings.read_text().replace('defaults.set(', 'benchmarkSetDefault('))
overlay = source / 'OverlayView.swift'
flags = []
if 'func applyRenderingAvailability()' in text:
    flags.append('PRISMA_PERFORMANCE_SUSPENSION')
if 'enum OrbViewport' in overlay.read_text():
    flags.append('PRISMA_PERFORMANCE_VIEWPORT')
if flags:
    manifest = out / 'app/Package.swift'
    settings = ', '.join(['.swiftLanguageMode(.v5)', *(f'.define("{flag}")' for flag in flags)])
    manifest.write_text(manifest.read_text().replace('.swiftLanguageMode(.v5)', settings))
text = overlay.read_text().replace('final class OverlayModel: ObservableObject {',
                                  'final class OverlayModel: ObservableObject {\n    var benchmarkFrames = 0')
text = text.replace('func frame(at time: TimeInterval) -> OrbFrame {',
                    'func frame(at time: TimeInterval) -> OrbFrame {\n        benchmarkFrames += 1')
overlay.write_text(text)
shutil.copy2(Path(__file__).with_name('BenchmarkMain.swift'), source / 'main.swift')
subprocess.run(['bash', 'build.sh'], cwd=out / 'app', check=True)
print(out / 'app/Prisma.app/Contents/MacOS/Prisma')

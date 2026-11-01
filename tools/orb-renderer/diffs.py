"""Frame-to-frame motion around each event. A cut shows up as a spike.

Usage: diffs.py <frames-dir> <fps> <event-seconds,...>
Render with the `silent` scenario so speech-driven motion does not hide cuts.

peak            largest change between two consecutive frames
max_step_change largest change of that change (a sudden jolt in speed)
"""
import glob
import os
import sys

from PIL import Image, ImageChops, ImageStat

frames_dir, fps = sys.argv[1], float(sys.argv[2])
events = [float(x) for x in sys.argv[3].split(',')]


def load(path):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    k = int(w * 0.42)
    return im.crop((w // 2 - k, h // 2 - k, w // 2 + k, h // 2 + k)).resize((200, 200), Image.BILINEAR)


diffs = []
previous = None
for path in sorted(glob.glob(os.path.join(frames_dir, 'f*.png'))):
    current = load(path)
    if previous is not None:
        diffs.append(sum(ImageStat.Stat(ImageChops.difference(current, previous)).mean) / 3)
    previous = current

for ev in events:
    start, end = int(ev * fps), min(len(diffs), int((ev + 1.6) * fps))
    segment = diffs[start:end]
    steady = diffs[max(0, start - int(0.5 * fps)):start]
    jolts = [abs(segment[i + 1] - segment[i]) for i in range(len(segment) - 1)]
    print('event %.2fs  peak=%.2f mean=%.2f steady_before=%.2f max_step_change=%.2f' % (
        ev, max(segment), sum(segment) / len(segment), sum(steady) / max(1, len(steady)), max(jolts)))

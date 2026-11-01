"""Contact sheet of a transition: one row of frames from just before each event.

Usage: sheet.py <frames-dir> <out.png> <fps> <event-seconds,...> [span=1.3] [step=3] [tile=170]
Example (cycle scenario): sheet.py frames sheet.png 30 1.0,3.6,6.6
"""
import os
import sys

from PIL import Image, ImageDraw

frames_dir, out, fps = sys.argv[1], sys.argv[2], float(sys.argv[3])
events = [float(x) for x in sys.argv[4].split(',')]
span = float(sys.argv[5]) if len(sys.argv) > 5 else 1.3
step = int(sys.argv[6]) if len(sys.argv) > 6 else 3
tile = int(sys.argv[7]) if len(sys.argv) > 7 else 170
before = 0.1

rows = [list(range(int(round((ev - before) * fps)), int(round((ev + span) * fps)) + 1, step)) for ev in events]
label = 14
sheet = Image.new('RGB', (max(len(r) for r in rows) * tile, len(rows) * (tile + label)), (12, 12, 14))
draw = ImageDraw.Draw(sheet)
for ri, row in enumerate(rows):
    for ci, f in enumerate(row):
        path = os.path.join(frames_dir, 'f%04d.png' % f)
        if not os.path.exists(path):
            continue
        im = Image.open(path).convert('RGB')
        w, h = im.size
        c = int(w * 0.46)  # crop around the 198 pt orb
        im = im.crop((w // 2 - c, h // 2 - c, w // 2 + c, h // 2 + c)).resize((tile, tile), Image.LANCZOS)
        x, y = ci * tile, ri * (tile + label)
        sheet.paste(im, (x, y + label))
        draw.text((x + 3, y + 1), '%+.2fs' % (f / fps - events[ri]), fill=(200, 200, 200))
sheet.save(out)
print(out, sheet.size)

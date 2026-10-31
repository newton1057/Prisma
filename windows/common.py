"""Protocol and text handling shared by the Windows app and agent hooks."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

SUPPORT = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'Prisma'
RUNTIME = SUPPORT / 'runtime.json'
CODE_BLOCK = re.compile(r'```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`')
TAG = re.compile(r'<\s*ForPri(?:s)?ma\s*>([\s\S]*?)(?:<\s*/\s*ForPri(?:s)?ma\s*>|\Z)', re.I)


def speech_text(text):
    text = str(text or '').replace('\r\n', '\n')
    no_code = CODE_BLOCK.sub(' ', text)
    matches = list(TAG.finditer(no_code))
    if matches and matches[-1].group(1).strip():
        text = matches[-1].group(1)
    else:
        headings = list(re.finditer(r'^\s*(?:#{1,6}\s*)?(?:\*\*)?For\s*Pri(?:s)?ma(?:\*\*)?\s*:?\s*', no_code, re.I | re.M))
        text = no_code[headings[-1].end():] if headings else no_code
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'<?https?://[^\s)>]+>?|\bwww\.[^\s)>]+', ' ', text, flags=re.I)
    text = re.sub(r'(?<!\w)(?:[A-Za-z]:\\|\\\\|~/|/(?:Users|tmp|var)/)[^\s,;)]*', ' ', text)
    text = re.sub(r'(?m)^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+)', '', text)
    text = re.sub(r'</?\s*ForPri(?:s)?ma\s*>|[*_~]', '', text, flags=re.I)
    return re.sub(r'\s+', ' ', text).strip()


def question_text(data):
    if isinstance(data, str):
        try: data = json.loads(data)
        except ValueError: return ''
    if not isinstance(data, dict): return ''
    parts = []
    for q in data.get('questions') or []:
        if not isinstance(q, dict): continue
        title = q.get('question') or q.get('title') or q.get('header') or ''
        options = []
        for item in q.get('options') or []:
            label = item if isinstance(item, str) else (item.get('label') or item.get('title') or item.get('value') or '') if isinstance(item, dict) else ''
            label = re.sub(r'\s*\((?:Recommended|Recomendado)\)', '', str(label), flags=re.I).strip()
            if label: options.append(label)
        if title: parts.append(str(title) + (' Opciones: ' + ', '.join(options) + '.' if options else ''))
    return ' '.join(parts) or str(data.get('message') or '')


def transcript_text(path):
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.readlines()[-200:]
        for line in reversed(lines):
            try: obj = json.loads(line)
            except ValueError: continue
            message = obj.get('payload') if obj.get('type') == 'response_item' else obj.get('message')
            if not isinstance(message, dict) or message.get('role') != 'assistant': continue
            content = message.get('content', [])
            if isinstance(content, str): return content
            texts = [p.get('text', '') for p in content if isinstance(p, dict) and p.get('type') in ('text', 'output_text')]
            if texts: return '\n'.join(texts)
    except (OSError, TypeError): pass
    return ''


def runtime():
    try:
        info = json.loads(RUNTIME.read_text(encoding='utf-8'))
        port = int(info['port'])
        if not 8787 <= port <= 8798 or not isinstance(info.get('token'), str): return None
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=1) as res:
            if json.load(res).get('app') != 'Prisma': return None
        return info
    except (OSError, ValueError, KeyError, TypeError): return None


def launch():
    executable = Path(sys.executable).with_name('pythonw.exe')
    app = SUPPORT / 'app.py'
    subprocess.Popen([str(executable), str(app)], cwd=str(app.parent), close_fds=True)


def send(payload, start=True):
    info = runtime()
    if not info and start:
        launch()
        for _ in range(40):
            time.sleep(.25)
            info = runtime()
            if info: break
    if not info: raise RuntimeError('Prisma no está disponible')
    request = urllib.request.Request(f"http://127.0.0.1:{info['port']}/speak", data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json', 'X-Prisma-Token': info['token']})
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.load(response)

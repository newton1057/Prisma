"""Configure agent hooks without replacing unrelated user configuration."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
from common import SUPPORT

ROOT = Path(__file__).resolve().parent.parent
CODEX = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex')
CLAUDE = Path.home() / '.claude'
OPENCODE = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'opencode'
MATCHER = 'AskUserQuestion|request_user_input|request_user_input_async|send_user_message_async|send_message_to_user_async|question'


def instruction(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding='utf-8') if path.exists() else ''
    if '<ForPrisma>' not in existing:
        addition = (ROOT / 'plugin' / 'AGENTS.md').read_text(encoding='utf-8')
        path.write_text(existing + ('\n\n' if existing.strip() else '') + addition, encoding='utf-8')


def hooks(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        data = json.loads(path.read_text(encoding='utf-8-sig'))
        if not isinstance(data, dict): raise ValueError(f'Configuración inválida: {path}')
        shutil.copy2(path, path.with_suffix(path.suffix + '.prisma-backup'))
    else: data = {}
    all_hooks = data.setdefault('hooks', {})
    # Forward slashes are accepted by Windows and by the shells used by agent hooks.
    python = (SUPPORT / 'venv' / 'Scripts' / 'python.exe').as_posix()
    script = (SUPPORT / 'hook.py').as_posix()
    command = f'"{python}" "{script}"'
    for event in ('Stop', 'PreToolUse', 'PermissionRequest'):
        entries = []
        for entry in all_hooks.get(event, []):
            entry = dict(entry)
            entry['hooks'] = [h for h in entry.get('hooks', []) if h.get('statusMessage') not in ('Prisma', 'CodexVoz')]
            if entry['hooks']: entries.append(entry)
        new = {'hooks': [{'type': 'command', 'command': command, 'timeout': 10, 'statusMessage': 'Prisma'}]}
        if event == 'PreToolUse': new['matcher'] = MATCHER
        entries.append(new)
        all_hooks[event] = entries
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)


def main():
    SUPPORT.mkdir(parents=True, exist_ok=True)
    for filename in ('common.py', 'hook.py', 'app.py'):
        shutil.copy2(ROOT / 'windows' / filename, SUPPORT / filename)
    instruction(CODEX / 'AGENTS.md')
    hooks(CODEX / 'hooks.json')
    print(f'Codex: hooks instalados en {CODEX}. Comprueba y autoriza los hooks si Codex lo solicita.')
    if CLAUDE.exists() or shutil.which('claude'):
        instruction(CLAUDE / 'CLAUDE.md')
        hooks(CLAUDE / 'settings.json')
        print('Claude Code: hooks instalados en la configuración del usuario.')
    else: print('Claude Code no detectado; vuelve a ejecutar el instalador después de instalarlo.')
    if OPENCODE.exists() or shutil.which('opencode'):
        (OPENCODE / 'plugins').mkdir(parents=True, exist_ok=True)
        (OPENCODE / 'skills' / 'prisma').mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'plugin' / 'opencode' / 'prisma.ts', OPENCODE / 'plugins' / 'prisma.ts')
        shutil.copy2(ROOT / 'plugin' / 'skills' / 'prisma' / 'SKILL.md', OPENCODE / 'skills' / 'prisma' / 'SKILL.md')
        print('OpenCode: plugin instalado.')
    else: print('OpenCode no detectado; vuelve a ejecutar el instalador después de instalarlo.')


if __name__ == '__main__': main()

"""Agent connections for the Windows app: status, install and removal."""
from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading

from common import SUPPORT, VERSION

CODEX = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex')
CLAUDE = Path(os.environ.get('CLAUDE_CONFIG_DIR') or Path.home() / '.claude')
OPENCODE = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'opencode'

TITLES = {'codex': 'Codex', 'claude': 'Claude Code', 'opencode': 'OpenCode'}
EXECUTABLES = {'codex': 'codex', 'claude': 'claude', 'opencode': 'opencode'}
MATCHER = 'AskUserQuestion|request_user_input|request_user_input_async|send_user_message_async|send_message_to_user_async|question'
EVENTS = ('Stop', 'PreToolUse', 'PermissionRequest')
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


@dataclass
class AgentInfo:
    key: str
    title: str
    state: str
    detail: str


def dist():
    return SUPPORT / 'plugin-dist'


def plugin_source():
    """The repository while developing, or the copy staged by the installer."""
    repo = Path(__file__).resolve().parent.parent / 'plugin'
    if (repo / 'AGENTS.md').is_file():
        return repo
    staged = dist() / 'plugin'
    if (staged / 'AGENTS.md').is_file():
        return staged
    raise RuntimeError('No encontré los archivos de integración de Prisma. Vuelve a ejecutar el instalador.')


def stage_dist():
    source = plugin_source()
    target = dist() / 'plugin'
    if os.path.normcase(os.path.realpath(source)) == os.path.normcase(os.path.realpath(target)):
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)
    return target


def ensure_support():
    """Copy the runtime files the hooks need, so they do not depend on the repository."""
    SUPPORT.mkdir(parents=True, exist_ok=True)
    source_dir = Path(__file__).resolve().parent
    for name in ('app.py', 'common.py', 'hook.py', 'agents.py', 'orb.py', 'overlay.py'):
        source = source_dir / name
        target = SUPPORT / name
        if os.path.normcase(os.path.realpath(source)) != os.path.normcase(os.path.realpath(target)):
            shutil.copy2(source, target)
    stage_dist()


def cli_available(kind):
    return shutil.which(EXECUTABLES[kind]) is not None


def hook_command():
    python = (SUPPORT / 'venv' / 'Scripts' / 'python.exe').as_posix()
    script = (SUPPORT / 'hook.py').as_posix()
    return f'"{python}" "{script}"'


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write_json(path, data):
    path = Path(path)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)


def backup(path):
    path = Path(path)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + '.prisma-backup'))


def is_prisma_hook(hook):
    return isinstance(hook, dict) and hook.get('statusMessage') in ('Prisma', 'CodexVoz')


def install_instruction(path):
    path = Path(path)
    body = (plugin_source() / 'AGENTS.md').read_text(encoding='utf-8').rstrip()
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding='utf-8') if path.exists() else ''
    if '<ForPrisma>' in existing:
        return
    addition = (existing.rstrip() + '\n\n' if existing.strip() else '') + body + '\n'
    path.write_text(addition, encoding='utf-8')


def remove_instruction(path):
    path = Path(path)
    if not path.exists():
        return
    text = path.read_text(encoding='utf-8')
    start = text.find('## Voice output for Prisma')
    if start < 0:
        return
    following = text.find('\n## ', start + 1)
    end = following if following >= 0 else len(text)
    updated = (text[:start] + text[end:]).strip()
    if updated:
        path.write_text(updated + '\n', encoding='utf-8')
    else:
        path.unlink()


def merge_hooks(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if path.exists():
        data = read_json(path)
        if not isinstance(data, dict):
            raise ValueError(f'Configuración inválida: {path}')
        backup(path)
    hooks = data.setdefault('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError(f'Configuración inválida: {path}')
    command = hook_command()
    for event in EVENTS:
        groups = []
        for group in hooks.get(event, []) or []:
            if not isinstance(group, dict):
                continue
            group = dict(group)
            inner = [h for h in group.get('hooks', []) or [] if not is_prisma_hook(h)]
            if inner:
                group['hooks'] = inner
                groups.append(group)
        fresh = {'hooks': [{'type': 'command', 'command': command, 'timeout': 10, 'statusMessage': 'Prisma'}]}
        if event == 'PreToolUse':
            fresh['matcher'] = MATCHER
        groups.append(fresh)
        hooks[event] = groups
    write_json(path, data)


def remove_hooks(path):
    path = Path(path)
    if not path.exists():
        return
    data = read_json(path)
    if not isinstance(data, dict):
        raise ValueError(f'Configuración inválida: {path}')
    backup(path)
    hooks = data.get('hooks')
    if isinstance(hooks, dict):
        for event in list(hooks):
            groups = []
            for group in hooks.get(event, []) or []:
                if not isinstance(group, dict):
                    continue
                group = dict(group)
                inner = [h for h in group.get('hooks', []) or [] if not is_prisma_hook(h)]
                if inner:
                    group['hooks'] = inner
                    groups.append(group)
            if groups:
                hooks[event] = groups
            else:
                hooks.pop(event, None)
        if not hooks:
            data.pop('hooks', None)
    if data:
        write_json(path, data)
    else:
        path.unlink()


def instruction_installed(path):
    try:
        return '<ForPrisma>' in Path(path).read_text(encoding='utf-8')
    except (OSError, UnicodeError):
        return False


def hooks_installed(path):
    try:
        data = read_json(path)
    except (OSError, ValueError, UnicodeError):
        return False
    hooks = data.get('hooks') if isinstance(data, dict) else None
    if not isinstance(hooks, dict):
        return False
    command = hook_command()
    for event in EVENTS:
        found = False
        for group in hooks.get(event, []) or []:
            if not isinstance(group, dict):
                continue
            for hook in group.get('hooks', []) or []:
                if isinstance(hook, dict) and hook.get('statusMessage') == 'Prisma' and hook.get('command') == command:
                    found = True
                    break
            if found:
                break
        if not found:
            return False
    return True


def codex_hooks_trusted():
    try:
        config = (CODEX / 'config.toml').read_text(encoding='utf-8')
    except (OSError, UnicodeError):
        return False
    return '[hooks.state]' in config and 'hooks.json:stop:0:0' in config


def status(kind):
    title = TITLES[kind]
    if not cli_available(kind):
        return AgentInfo(kind, title, 'missing', 'No encontrado en este PC')

    if kind == 'codex':
        installed = hooks_installed(CODEX / 'hooks.json')
        instructed = instruction_installed(CODEX / 'AGENTS.md')
        trusted = installed and codex_hooks_trusted()
        missing = []
        if not installed:
            missing.append('hooks')
        if not instructed:
            missing.append('instrucciones')
        if installed and not trusted:
            missing.append('confianza')
        if not missing:
            return AgentInfo(kind, title, 'connected', 'Conectado')
        if not installed and not instructed:
            return AgentInfo(kind, title, 'disconnected', 'No conectado')
        return AgentInfo(kind, title, 'incomplete', 'Falta: ' + ', '.join(missing))

    if kind == 'claude':
        installed = hooks_installed(CLAUDE / 'settings.json')
        instructed = instruction_installed(CLAUDE / 'CLAUDE.md')
        if installed and instructed:
            return AgentInfo(kind, title, 'connected', 'Conectado')
        if not installed and not instructed:
            return AgentInfo(kind, title, 'disconnected', 'No conectado')
        missing = ([] if installed else ['hooks']) + ([] if instructed else ['instrucciones'])
        return AgentInfo(kind, title, 'incomplete', 'Falta: ' + ', '.join(missing))

    try:
        source = plugin_source()
        expected = (source / 'opencode' / 'prisma.ts').read_bytes()
    except (OSError, RuntimeError):
        return AgentInfo(kind, title, 'incomplete', 'Faltan archivos de integración')
    plugin = OPENCODE / 'plugins' / 'prisma.ts'
    skill = OPENCODE / 'skills' / 'prisma' / 'SKILL.md'
    if not plugin.exists() and not skill.exists():
        return AgentInfo(kind, title, 'disconnected', 'No conectado')
    if plugin.exists():
        try:
            if plugin.read_bytes() != expected:
                return AgentInfo(kind, title, 'incomplete', 'Plugin desactualizado')
        except OSError:
            return AgentInfo(kind, title, 'incomplete', 'No pude leer el plugin')
    missing = []
    if not plugin.exists():
        missing.append('plugin')
    if not skill.exists():
        missing.append('skill')
    if missing:
        return AgentInfo(kind, title, 'incomplete', 'Falta: ' + ', '.join(missing))
    return AgentInfo(kind, title, 'connected', 'Conectado')


def statuses():
    return [status(kind) for kind in ('codex', 'claude', 'opencode')]


def connect(kind):
    ensure_support()
    if kind == 'codex':
        install_instruction(CODEX / 'AGENTS.md')
        merge_hooks(CODEX / 'hooks.json')
        if not cli_available('codex'):
            return ['Codex no está instalado; los hooks quedarán listos para cuando lo instales.']
        if not trust_codex_hooks():
            return ['No pude marcar los hooks como confiables. Codex puede pedirte que los autorices al abrirlo.']
        return []
    if kind == 'claude':
        install_instruction(CLAUDE / 'CLAUDE.md')
        merge_hooks(CLAUDE / 'settings.json')
        return []
    source = plugin_source()
    (OPENCODE / 'plugins').mkdir(parents=True, exist_ok=True)
    (OPENCODE / 'skills' / 'prisma').mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'opencode' / 'prisma.ts', OPENCODE / 'plugins' / 'prisma.ts')
    shutil.copy2(source / 'skills' / 'prisma' / 'SKILL.md', OPENCODE / 'skills' / 'prisma' / 'SKILL.md')
    reload_opencode()
    return []


def disconnect(kind):
    if kind == 'codex':
        remove_hooks(CODEX / 'hooks.json')
        remove_instruction(CODEX / 'AGENTS.md')
    elif kind == 'claude':
        remove_hooks(CLAUDE / 'settings.json')
        remove_instruction(CLAUDE / 'CLAUDE.md')
    else:
        (OPENCODE / 'plugins' / 'prisma.ts').unlink(missing_ok=True)
        (OPENCODE / 'skills' / 'prisma' / 'SKILL.md').unlink(missing_ok=True)
        reload_opencode()


def _command(executable, args):
    if os.name == 'nt' and executable.lower().endswith(('.cmd', '.bat')):
        return [os.environ.get('COMSPEC', 'cmd.exe'), '/d', '/c', executable] + list(args)
    return [executable] + list(args)


def reload_opencode():
    executable = shutil.which('opencode')
    if not executable:
        return
    try:
        subprocess.run(
            _command(executable, ['reload']),
            timeout=20,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=NO_WINDOW,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def _codex_command():
    executable = shutil.which('codex')
    return _command(executable, ['app-server']) if executable else None


def trust_codex_hooks(timeout=20):
    """Mark the Prisma hooks as trusted through Codex's app-server protocol.

    Codex restarts its app server after answering ``hooks/list``, so the trust
    write goes in a second short session with all the messages batched.
    """
    hooks_file = CODEX / 'hooks.json'
    command = _codex_command()
    if not hooks_file.is_file() or not command:
        return False
    initialize = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                  'params': {'clientInfo': {'name': 'prisma-app', 'version': VERSION}}}
    initialized = {'jsonrpc': '2.0', 'method': 'initialized', 'params': {}}
    listing = {'jsonrpc': '2.0', 'id': 2, 'method': 'hooks/list',
               'params': {'cwds': [str(SUPPORT)]}}
    response = _codex_session(command, [initialize, initialized, listing], 2, min(timeout, 12))
    if not response:
        return False
    target = os.path.normcase(os.path.realpath(hooks_file))
    updates = {}
    result = response.get('result') if isinstance(response, dict) else None
    for item in (result or {}).get('data') or []:
        for hook in item.get('hooks') or []:
            source = hook.get('sourcePath')
            if not source or os.path.normcase(os.path.realpath(source)) != target:
                continue
            if hook.get('statusMessage') != 'Prisma':
                continue
            key, current = hook.get('key'), hook.get('currentHash')
            if key and current:
                updates[key] = {'trusted_hash': current}
    if not updates:
        return False
    write = {'jsonrpc': '2.0', 'id': 3, 'method': 'config/batchWrite',
             'params': {'edits': [{'keyPath': 'hooks.state', 'value': updates,
                                   'mergeStrategy': 'upsert'}], 'reloadUserConfig': True}}
    response = _codex_session(command, [initialize, initialized, write], 3, timeout)
    return bool(response and (response.get('result') or {}).get('status') == 'ok')


def _codex_session(command, messages, wait_id, timeout):
    payload = ''.join(json.dumps(message, ensure_ascii=False) + '\n' for message in messages)
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding='utf-8',
            errors='replace',
            bufsize=1,
            creationflags=NO_WINDOW,
        )
    except OSError:
        return None
    watchdog = threading.Timer(timeout, process.kill)
    watchdog.daemon = True
    watchdog.start()
    try:
        process.stdin.write(payload)
        process.stdin.flush()
        for line in process.stdout:
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if isinstance(message, dict) and message.get('id') == wait_id:
                return message
        return None
    except (OSError, ValueError):
        return None
    finally:
        watchdog.cancel()
        for stream in (process.stdin, process.stdout):
            try:
                stream.close()
            except OSError:
                pass
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

import json
import os
from pathlib import Path
import queue
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

_support_dir = tempfile.TemporaryDirectory()
os.environ['LOCALAPPDATA'] = _support_dir.name
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'windows'))
import agents
import common
import hook
import install
import app


class TextTests(unittest.TestCase):
    def test_extract_last_real_tag_and_clean(self):
        text = '```<ForPrisma>Ignora esto</ForPrisma>```\n<ForPrisma>Listo. Visita [sitio](https://example.com) C:\\Users\\a\\x</ForPrisma>'
        self.assertEqual(common.speech_text(text), 'Listo. Visita sitio')
    def test_question_options_and_json_string(self):
        self.assertEqual(common.question_text(json.dumps({'questions': [{'title': '¿Cuál?', 'options': ['Uno', {'label': 'Dos (Recommended)'}]}]})), '¿Cuál? Opciones: Uno, Dos.')
    def test_transcript(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'turn.jsonl'
            p.write_text(json.dumps({'type':'response_item','payload':{'role':'assistant','content':[{'type':'output_text','text':'Hola'}]}}), encoding='utf-8')
            self.assertEqual(common.transcript_text(p), 'Hola')
    def test_hook_questions(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(hook, 'SUPPORT', Path(directory)), patch.object(hook, 'send') as send:
            hook.main({'hook_event_name':'PreToolUse', 'tool_name':'request_user_input', 'tool_input':{'questions':[{'question':'¿Continuar?', 'options':['Sí','No']}]}})
            self.assertEqual(send.call_args.args[0]['text'], '¿Continuar? Opciones: Sí, No.')
            hook.main({'hook_event_name':'PreToolUse', 'tool_name':'request_user_input', 'tool_input':{'questions':[{'question':'¿Continuar?', 'options':['Sí','No']}]}})
            self.assertEqual(send.call_count, 1)


class ServerTests(unittest.TestCase):
    def test_auth_and_routing(self):
        server = app.Server(('127.0.0.1', 0), app.Handler)
        server.token = 'secret'; server.events = queue.Queue()
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(base + '/health') as r:
                health = json.load(r)
                self.assertEqual(health['app'], 'Prisma')
                self.assertEqual(health['version'], common.VERSION)
            data = json.dumps({'text':'Hola'}).encode()
            with self.assertRaises(urllib.error.HTTPError) as e: urllib.request.urlopen(urllib.request.Request(base + '/speak', data=data))
            self.assertEqual(e.exception.code, 401)
            request = urllib.request.Request(base + '/speak', data=data, headers={'X-Prisma-Token':'secret'})
            with urllib.request.urlopen(request) as r: self.assertTrue(json.load(r)['ok'])
            self.assertEqual(server.events.get_nowait(), ('speak', {'text':'Hola'}))
        finally: server.shutdown(); server.server_close(); thread.join()


class AgentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.codex = root / 'codex'
        self.claude = root / 'claude'
        self.opencode = root / 'opencode'
        self.support = root / 'Prisma'
        self.ensure = patch.object(agents, 'ensure_support')
        patches = [
            patch.object(agents, 'CODEX', self.codex),
            patch.object(agents, 'CLAUDE', self.claude),
            patch.object(agents, 'OPENCODE', self.opencode),
            patch.object(agents, 'SUPPORT', self.support),
            self.ensure,
        ]
        for item in patches: item.start()
        self.addCleanup(lambda: [item.stop() for item in patches])

    def connect(self, kind, cli=True, trusted=True):
        with patch.object(agents, 'cli_available', return_value=cli), patch.object(agents, 'trust_codex_hooks', return_value=trusted):
            return agents.connect(kind)

    def status(self, kind, cli=True):
        with patch.object(agents, 'cli_available', return_value=cli):
            return agents.status(kind)

    def test_codex_connect_is_idempotent_and_removable(self):
        warnings = self.connect('codex')
        self.assertEqual(warnings, [])
        hooks = json.loads((self.codex / 'hooks.json').read_text(encoding='utf-8'))['hooks']
        for event in agents.EVENTS:
            self.assertEqual(len(hooks[event]), 1)
            self.assertEqual(hooks[event][0]['hooks'][0]['statusMessage'], 'Prisma')
        instructions = (self.codex / 'AGENTS.md').read_text(encoding='utf-8')
        self.assertIn('<ForPrisma>', instructions)

        (self.codex / 'config.toml').write_text('[hooks.state]\n"hooks.json:stop:0:0" = "x"\n', encoding='utf-8')
        self.assertEqual(self.status('codex').state, 'connected')

        self.connect('codex')
        self.assertEqual((self.codex / 'AGENTS.md').read_text(encoding='utf-8').count('## Voice output for Prisma'), 1)
        hooks = json.loads((self.codex / 'hooks.json').read_text(encoding='utf-8'))['hooks']
        for event in agents.EVENTS: self.assertEqual(len(hooks[event]), 1)

        agents.disconnect('codex')
        self.assertFalse((self.codex / 'hooks.json').exists())
        self.assertFalse((self.codex / 'AGENTS.md').exists())
        self.assertEqual(self.status('codex').state, 'disconnected')

    def test_codex_trust_is_reported_as_incomplete(self):
        self.connect('codex', trusted=False)
        info = self.status('codex')
        self.assertEqual(info.state, 'incomplete')
        self.assertIn('confianza', info.detail)

    def test_preserves_unrelated_hooks_and_backs_up(self):
        path = self.codex / 'hooks.json'
        path.parent.mkdir(parents=True)
        original = {'other': 42, 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'other'}]}], 'SessionStart': [{'hooks': [{'type': 'command', 'command': 'start'}]}]}}
        path.write_text(json.dumps(original), encoding='utf-8')
        self.connect('codex')
        data = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(data['other'], 42)
        self.assertEqual(len(data['hooks']['Stop']), 2)
        self.assertEqual(data['hooks']['Stop'][0]['hooks'][0]['command'], 'other')
        self.assertEqual(data['hooks']['SessionStart'], original['hooks']['SessionStart'])
        backup = json.loads((self.codex / 'hooks.json.prisma-backup').read_text(encoding='utf-8'))
        self.assertEqual(backup, original)
        agents.disconnect('codex')
        data = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(data['hooks']['Stop'], original['hooks']['Stop'])
        self.assertEqual(data['hooks']['SessionStart'], original['hooks']['SessionStart'])

    def test_instruction_block_preserves_existing_text(self):
        path = self.codex / 'AGENTS.md'
        path.parent.mkdir(parents=True)
        path.write_text('# Mis instrucciones\n', encoding='utf-8')
        agents.install_instruction(path)
        agents.install_instruction(path)
        text = path.read_text(encoding='utf-8')
        self.assertTrue(text.startswith('# Mis instrucciones'))
        self.assertEqual(text.count('## Voice output for Prisma'), 1)
        agents.remove_instruction(path)
        self.assertEqual(path.read_text(encoding='utf-8'), '# Mis instrucciones\n')

    def test_claude_connection_and_removal(self):
        self.claude.mkdir(parents=True)
        (self.claude / 'CLAUDE.md').write_text('# Mine\n', encoding='utf-8')
        (self.claude / 'settings.json').write_text(json.dumps({'theme': 'dark'}), encoding='utf-8')
        self.assertEqual(self.connect('claude'), [])
        info = self.status('claude')
        self.assertEqual(info.state, 'connected')
        settings = json.loads((self.claude / 'settings.json').read_text(encoding='utf-8'))
        self.assertEqual(settings['theme'], 'dark')
        self.assertEqual(set(settings['hooks']), set(agents.EVENTS))
        self.assertIn('<ForPrisma>', (self.claude / 'CLAUDE.md').read_text(encoding='utf-8'))
        agents.disconnect('claude')
        self.assertEqual(json.loads((self.claude / 'settings.json').read_text(encoding='utf-8')), {'theme': 'dark'})
        self.assertEqual((self.claude / 'CLAUDE.md').read_text(encoding='utf-8'), '# Mine\n')
        self.assertEqual(self.status('claude').state, 'disconnected')

    def test_opencode_install_update_and_remove(self):
        source = agents.plugin_source()
        with patch.object(agents, 'reload_opencode') as reload:
            self.assertEqual(self.connect('opencode'), [])
            self.assertEqual(reload.call_count, 1)
        plugin = self.opencode / 'plugins' / 'prisma.ts'
        skill = self.opencode / 'skills' / 'prisma' / 'SKILL.md'
        self.assertEqual(plugin.read_bytes(), (source / 'opencode' / 'prisma.ts').read_bytes())
        self.assertEqual(skill.read_bytes(), (source / 'skills' / 'prisma' / 'SKILL.md').read_bytes())
        self.assertEqual(self.status('opencode').state, 'connected')
        plugin.write_text('viejo', encoding='utf-8')
        info = self.status('opencode')
        self.assertEqual(info.state, 'incomplete')
        self.assertEqual(info.detail, 'Plugin desactualizado')
        with patch.object(agents, 'reload_opencode'):
            self.connect('opencode')
        self.assertEqual(self.status('opencode').state, 'connected')
        with patch.object(agents, 'reload_opencode'):
            agents.disconnect('opencode')
        self.assertFalse(plugin.exists())
        self.assertFalse(skill.exists())
        self.assertEqual(self.status('opencode').state, 'disconnected')

    def test_missing_cli_is_reported(self):
        for kind in ('codex', 'claude', 'opencode'):
            info = self.status(kind, cli=False)
            self.assertEqual(info.state, 'missing')
        warnings = self.connect('codex', cli=False)
        self.assertEqual(len(warnings), 1)
        self.assertIn('Codex no está instalado', warnings[0])
        self.assertTrue((self.codex / 'hooks.json').exists())

    def test_ensure_support_stages_runtime_and_plugin(self):
        self.ensure.stop()
        try:
            agents.ensure_support()
        finally:
            self.ensure.start()
        for name in ('app.py', 'common.py', 'hook.py', 'agents.py'):
            self.assertTrue((self.support / name).exists(), name)
        self.assertTrue((self.support / 'plugin-dist' / 'plugin' / 'AGENTS.md').exists())

    def test_trust_codex_hooks_uses_two_batched_sessions(self):
        hooks_file = self.codex / 'hooks.json'
        hooks_file.parent.mkdir(parents=True)
        hooks_file.write_text('{}', encoding='utf-8')
        root = Path(self.temp.name)
        log = root / 'codex.log'
        script = root / 'fake_codex.py'
        script.write_text(
            'import json, sys\n'
            'from pathlib import Path\n'
            'log = Path(sys.argv[1])\n'
            'source = sys.argv[2]\n'
            'for line in sys.stdin:\n'
            '    line = line.strip()\n'
            '    if not line: continue\n'
            '    with log.open("a", encoding="utf-8") as handle: handle.write(line + "\\n")\n'
            '    message = json.loads(line)\n'
            '    if message.get("method") == "hooks/list":\n'
            '        hooks = [{"sourcePath": source, "statusMessage": "Prisma", "key": "hooks.json:stop:0:0", "currentHash": "abc123"}]\n'
            '        print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": {"data": [{"hooks": hooks}]}}), flush=True)\n'
            '    elif message.get("method") == "config/batchWrite":\n'
            '        print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": {"status": "ok"}}), flush=True)\n',
            encoding='utf-8',
        )
        command = [sys.executable, str(script), str(log), str(hooks_file)]
        with patch.object(agents, '_codex_command', return_value=command):
            self.assertTrue(agents.trust_codex_hooks(timeout=10))
        messages = [json.loads(line) for line in log.read_text(encoding='utf-8').splitlines()]
        methods = [message.get('method') for message in messages]
        self.assertIn('hooks/list', methods)
        self.assertIn('config/batchWrite', methods)
        write = next(message for message in messages if message.get('method') == 'config/batchWrite')
        self.assertEqual(write['params']['edits'][0]['value'], {'hooks.json:stop:0:0': {'trusted_hash': 'abc123'}})

    def test_trust_codex_hooks_rejects_unknown_hooks(self):
        hooks_file = self.codex / 'hooks.json'
        hooks_file.parent.mkdir(parents=True)
        hooks_file.write_text('{}', encoding='utf-8')
        root = Path(self.temp.name)
        script = root / 'fake_codex.py'
        script.write_text(
            'import json, sys\n'
            'for line in sys.stdin:\n'
            '    message = json.loads(line)\n'
            '    if message.get("method") == "hooks/list":\n'
            '        print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": {"data": []}}), flush=True)\n',
            encoding='utf-8',
        )
        with patch.object(agents, '_codex_command', return_value=[sys.executable, str(script)]):
            self.assertFalse(agents.trust_codex_hooks(timeout=10))


class InstallTests(unittest.TestCase):
    def test_detected_uses_cli_or_config_folder(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(agents, 'cli_available', return_value=False), patch.object(agents, 'CLAUDE', Path(directory) / 'claude'):
            self.assertFalse(install.detected('claude'))
            (Path(directory) / 'claude').mkdir()
            self.assertTrue(install.detected('claude'))


class AgentUiTests(unittest.TestCase):
    def test_worker_reports_result_and_error(self):
        instance = object.__new__(app.App)
        instance.events = queue.Queue()
        with patch.object(app.agents, 'connect', return_value=['aviso']):
            instance.agent_worker('codex', 'connect')
        self.assertEqual(instance.events.get_nowait(), ('agent-done', ('codex', ['aviso'], '')))
        with patch.object(app.agents, 'connect', side_effect=ValueError('roto')):
            instance.agent_worker('codex', 'connect')
        self.assertEqual(instance.events.get_nowait(), ('agent-done', ('codex', [], 'roto')))

    def test_finished_clears_overrides_and_keeps_warnings(self):
        instance = object.__new__(app.App)
        instance.agent_busy = 'codex'
        instance.agent_overrides = {'codex': ('working', 'Conectando…'), 'claude': ('working', 'Conectando…')}
        instance.agent_warnings = []
        with patch.object(instance, 'refresh_agents') as refresh:
            instance.agent_finished('codex', ['aviso'], '')
        self.assertIsNone(instance.agent_busy)
        self.assertEqual(instance.agent_overrides, {'claude': ('working', 'Conectando…')})
        self.assertEqual(instance.agent_warnings, ['aviso'])
        refresh.assert_called_once()


if __name__ == '__main__': unittest.main()

import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import hashlib
import zipfile

from PIL import Image, ImageChops, ImageStat

_support_dir = tempfile.TemporaryDirectory()
os.environ['LOCALAPPDATA'] = _support_dir.name
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'windows'))
import agents
import common
import hook
import install
import orb
import overlay
import app
import updater


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
                self.assertEqual(health['build'], common.BUILD)
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
        for name in ('app.py', 'common.py', 'hook.py', 'agents.py', 'orb.py', 'overlay.py'):
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


class OrbTests(unittest.TestCase):
    def test_every_palette_has_a_title_and_default_is_prisma(self):
        self.assertEqual(set(orb.THEME_TITLES), set(orb.PALETTES))
        self.assertEqual(len(orb.PALETTES), 10)
        self.assertEqual(app.DEFAULTS['theme'], 'prisma')
        self.assertEqual(set(app.THEME_KEYS), set(orb.THEME_TITLES.values()))

    def test_idle_frame_has_transparent_corners_and_a_visible_body(self):
        image = orb.frame_image(orb.OrbFrame(0.0, voice=0, idle=1, idle_phase=2.37))
        self.assertEqual(image.size, (orb.CANVAS, orb.CANVAS))
        self.assertEqual(image.mode, 'RGBA')
        self.assertEqual(image.getpixel((0, 0))[3], 0)
        self.assertGreater(image.getpixel((orb.CANVAS // 2, orb.CANVAS // 2))[3], 200)

    def test_voice_frame_keeps_transparent_corners(self):
        image = orb.frame_image(orb.OrbFrame(0.0, voice=1, idle=0, speaking=1))
        alpha = image.getchannel('A')
        far = orb.CANVAS - 1
        for corner in ((0, 0), (far, 0), (0, far), (far, far)):
            self.assertEqual(alpha.getpixel(corner), 0, corner)
        self.assertGreater(alpha.getpixel((orb.CANVAS // 2, orb.CANVAS // 2)), 200)

    def test_layer_handoffs_do_not_pop(self):
        # The moving light swaps paths near voice 0.06, the voice glass fades
        # in at 0.001 and the idle glow fades out at 1.0. Each pair straddles
        # one of those handoffs, so a hard switch would show a large jump.
        pairs = [
            (0.0005, 0.002),
            (orb.LIGHT_CROSSFADE - 0.002, orb.LIGHT_CROSSFADE + 0.002),
            (0.998, 1.0),
        ]
        for before, after in pairs:
            images = [
                orb.frame_image(orb.OrbFrame(1.0, voice=voice, idle=1 - voice))
                for voice in (before, after)
            ]
            jump = sum(ImageStat.Stat(ImageChops.difference(*images)).mean)
            self.assertLess(jump, 6.0, (before, after, jump))

    def test_animator_eases_between_idle_and_voice(self):
        animator = orb.OrbAnimator('aurora')
        now = 0.0
        animator.frame(now)
        idle = animator.frame(now)
        self.assertLess(idle.voice, 0.1)
        animator.set_speaking(True)
        for _ in range(12):
            now += 1 / 30
            voice = animator.frame(now)
        self.assertGreater(voice.voice, 0.2)
        self.assertLess(voice.voice, 0.4)
        for _ in range(30):
            now += 1 / 30
            voice = animator.frame(now)
        self.assertGreater(voice.voice, 0.95)
        self.assertAlmostEqual(voice.idle, 1 - voice.voice)
        self.assertEqual(voice.theme, 'aurora')
        animator.set_speaking(False)
        for _ in range(60):
            now += 1 / 30
            resting = animator.frame(now)
        self.assertLess(resting.voice, 0.05)


class OverlayTests(unittest.TestCase):
    def test_placement_matches_the_tk_overlay(self):
        self.assertEqual(overlay.placement('top', 1920, 1080), (870, 25))
        self.assertEqual(overlay.placement('bottom', 1920, 1080), (870, 860))
        self.assertEqual(overlay.placement('center', 1920, 1080), (870, 450))
        self.assertEqual(overlay.placement('corner', 1920, 1080), (1720, 860))
        self.assertEqual(overlay.placement('top', 100, 100), (0, 25))
        self.assertEqual(overlay.placement('bottom', 100, 100), (0, 0))

    def test_premultiplied_bgra(self):
        image = Image.new('RGBA', (1, 1), (200, 100, 50, 128))
        self.assertEqual(overlay.premultiplied_bgra(image), b'\x19\x32\x64\x80')

    def test_scaled_keeps_the_canvas_and_fades_alpha(self):
        image = Image.new('RGBA', (10, 10), (255, 255, 255, 200))
        smaller = overlay.scaled(image, 0.5)
        self.assertEqual(smaller.size, image.size)
        self.assertEqual(smaller.getpixel((0, 0))[3], 0)
        self.assertGreater(smaller.getpixel((5, 5))[3], 0)
        faded = overlay.with_alpha(image, 0.5)
        self.assertEqual(faded.getpixel((0, 0))[3], 100)

    def test_overlay_is_a_noop_off_windows(self):
        widget = overlay.OrbOverlay('missing-theme', 'top')
        self.assertEqual(widget.theme, 'prisma')
        if os.name != 'nt':
            widget.start(); widget.show(); widget.set_theme('solar'); widget.hide(immediate=True); widget.stop()
            self.assertIsNone(widget._worker)


class UpdateTests(unittest.TestCase):
    # Signed by the real UpdateSigner with the same key the macOS app uses,
    # over the six bytes "prueba". Keeping a real signature means a change in
    # the signed text layout fails here, not in production.
    SIGNED = {
        'version': '1.0.3',
        'build': 3,
        'file': 'windows/versiones/1.0.3/Prisma-Windows-1.0.3.zip',
        'size': 6,
        'sha256': '655e786674d9d3e77bc05ed1de37b4b6bc89f788829f9f3c679e7687b410c89b',
        'notes': 'Notas de prueba',
        'signature': 'BxzAfm3ZH5HL3WvFxcTo8h+V2mi9+/EpJJPQ9P1qpxrdCAYrJm9m4kzYd4a3IJz53V1pRPeLaySjg2d2QImkBA==',
    }

    class Response:
        status = 200
        def __init__(self, payload): self.payload = payload; self.position = 0
        def read(self, size=-1):
            if size is None or size < 0: size = len(self.payload) - self.position
            chunk = self.payload[self.position:self.position + size]
            self.position += len(chunk)
            return chunk
        def __enter__(self): return self
        def __exit__(self, *args): return False

    class OneByteResponse(Response):
        def read(self, size=-1): return super().read(1)

    def signed(self, **changes):
        return updater.Manifest.from_json(json.dumps({**self.SIGNED, **changes}))

    def opener(self, payload, response=None):
        response = response or self.Response
        return lambda request, timeout=None: response(payload)

    def test_published_manifest_has_a_valid_signature(self):
        self.assertTrue(self.signed().is_valid())

    def test_tampering_any_signed_field_breaks_the_signature(self):
        changes = {
            'version': '9.9.9',
            'build': 99,
            'file': 'windows/versiones/9.9.9/Prisma-Windows-9.9.9.zip',
            'size': 7,
            'sha256': '0' * 64,
            'notes': 'Otras notas',
        }
        for field, value in changes.items():
            self.assertFalse(self.signed(**{field: value}).is_valid(), field)
        signature = self.SIGNED['signature']
        altered = ('A' if signature[0] != 'A' else 'B') + signature[1:]
        self.assertFalse(self.signed(signature=altered).is_valid())

    def test_signed_text_uses_the_swift_field_order(self):
        expected = '\n'.join([self.SIGNED['version'], '3', self.SIGNED['file'], '6',
                              self.SIGNED['sha256'], self.SIGNED['notes']])
        self.assertEqual(self.signed().signed_text(), expected)

    def test_manifest_rejects_bad_types_and_paths(self):
        for changes in ({'build': True}, {'build': '3'}, {'size': 0}, {'size': True},
                        {'file': '../x.zip'}, {'file': '/x.zip'}, {'file': 'C:/x.zip'},
                        {'file': 'windows//x.zip'}, {'sha256': 'x' * 64},
                        {'signature': 'abc'}, {'version': '1.0.3\nx'}):
            with self.assertRaises(updater.UpdateError, msg=changes):
                self.signed(**changes)

    def test_check_only_returns_newer_builds(self):
        payload = json.dumps(self.SIGNED).encode()
        self.assertIsNone(updater.check(3, opener=self.opener(payload)))
        found = updater.check(2, opener=self.opener(payload))
        self.assertEqual(found.version, '1.0.3')
        self.assertEqual(found.build, 3)

    def test_check_rejects_a_tampered_manifest(self):
        payload = json.dumps({**self.SIGNED, 'notes': 'Otras notas'}).encode()
        with self.assertRaises(updater.UpdateError):
            updater.check(2, opener=self.opener(payload))

    def test_download_reports_progress_and_verifies_the_size(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.signed(size=4, sha256=hashlib.sha256(b'abcd').hexdigest(),
                                   file='windows/versiones/1.0.3/Prisma-Windows-1.0.3.zip')
            destination = Path(directory) / 'update.zip'
            progress = []
            updater.download(manifest, destination, opener=self.opener(b'abcd', self.OneByteResponse),
                             progress=progress.append)
            self.assertEqual(destination.read_bytes(), b'abcd')
            self.assertEqual(progress, [0.25, 0.5, 0.75, 1.0])
            updater.verify_package(destination, manifest)
            with self.assertRaises(updater.UpdateError):
                updater.download(manifest, destination, opener=self.opener(b'abc'))
            self.assertFalse(destination.exists())

    def package(self, directory, version='1.0.3', build=3):
        path = Path(directory) / 'Prisma-Windows.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Prisma/windows/app.py', '# app\n')
            archive.writestr('Prisma/windows/common.py', f"VERSION = '{version}'\nBUILD = {build}\n")
            archive.writestr('Prisma/plugin/AGENTS.md', '# plugin\n')
        data = path.read_bytes()
        return path, len(data), hashlib.sha256(data).hexdigest()

    def manifest_for(self, size, sha256, version='1.0.3', build=3):
        return self.signed(version=version, build=build, size=size, sha256=sha256)

    def test_prepare_requires_the_announced_version(self):
        with tempfile.TemporaryDirectory() as directory:
            package, size, digest = self.package(directory)
            manifest = self.manifest_for(size, digest)
            staged = updater.prepare(package, manifest, Path(directory) / 'work')
            self.assertEqual(updater.staged_version(staged), ('1.0.3', 3))
            self.assertTrue((staged / 'windows' / 'app.py').is_file())
            package, size, digest = self.package(directory, build=4)
            with self.assertRaises(updater.UpdateError):
                updater.prepare(package, self.manifest_for(size, digest), Path(directory) / 'other')
            package, size, digest = self.package(directory)
            with self.assertRaises(updater.UpdateError):
                updater.prepare(package, self.manifest_for(size, '0' * 64), Path(directory) / 'third')

    def test_extract_rejects_paths_outside_the_workspace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / 'evil.zip'
            with zipfile.ZipFile(package, 'w') as archive:
                archive.writestr('../evil.txt', 'x')
            with self.assertRaises(updater.UpdateError):
                updater.extract(package, root / 'out')
            self.assertFalse((root / 'evil.txt').exists())
            with zipfile.ZipFile(package, 'w') as archive:
                archive.writestr('/evil.txt', 'x')
            with self.assertRaises(updater.UpdateError):
                updater.extract(package, root / 'out')

    def test_install_files_keeps_settings_and_can_roll_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); support = root / 'Prisma'; staged = root / 'nuevo' / 'Prisma'
            support.mkdir()
            (support / 'app.py').write_text('old', encoding='utf-8')
            (support / 'settings.json').write_text('{"theme":"solar"}', encoding='utf-8')
            (support / 'venv' / 'Scripts').mkdir(parents=True)
            (support / 'venv' / 'Scripts' / 'python.exe').write_text('python', encoding='utf-8')
            (support / 'voices').mkdir()
            (support / 'voices' / 'model.onnx').write_text('voice', encoding='utf-8')
            (support / 'plugin-dist' / 'plugin').mkdir(parents=True)
            (support / 'plugin-dist' / 'plugin' / 'AGENTS.md').write_text('old plugin', encoding='utf-8')
            (staged / 'windows').mkdir(parents=True)
            (staged / 'windows' / 'app.py').write_text('new', encoding='utf-8')
            (staged / 'windows' / 'common.py').write_text("VERSION = '1.0.3'\nBUILD = 3\n", encoding='utf-8')
            (staged / 'windows' / 'requirements.txt').write_text('Pillow>=10,<13\n', encoding='utf-8')
            (staged / 'plugin').mkdir(parents=True)
            (staged / 'plugin' / 'AGENTS.md').write_text('new plugin', encoding='utf-8')
            self.assertTrue(updater.requirements_changed(staged, support))
            changed = updater.install_files(staged, support)
            self.assertIn('app.py', changed)
            self.assertEqual((support / 'app.py').read_text(encoding='utf-8'), 'new')
            self.assertEqual((support / 'settings.json').read_text(encoding='utf-8'), '{"theme":"solar"}')
            self.assertEqual((support / 'venv' / 'Scripts' / 'python.exe').read_text(encoding='utf-8'), 'python')
            self.assertEqual((support / 'voices' / 'model.onnx').read_text(encoding='utf-8'), 'voice')
            self.assertEqual((support / 'plugin-dist' / 'plugin' / 'AGENTS.md').read_text(encoding='utf-8'), 'new plugin')
            self.assertFalse(updater.requirements_changed(staged, support))
            self.assertTrue((support / 'update-backup' / 'app.py').is_file())
            self.assertTrue(updater.rollback(support))
            self.assertEqual((support / 'app.py').read_text(encoding='utf-8'), 'old')
            self.assertEqual((support / 'plugin-dist' / 'plugin' / 'AGENTS.md').read_text(encoding='utf-8'), 'old plugin')
            self.assertEqual((support / 'settings.json').read_text(encoding='utf-8'), '{"theme":"solar"}')
            self.assertFalse((support / 'update-backup').exists())

    def test_finish_update_removes_the_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); support = root / 'Prisma'; staged = root / 'nuevo' / 'Prisma'
            support.mkdir(); (support / 'app.py').write_text('old', encoding='utf-8')
            (staged / 'windows').mkdir(parents=True)
            (staged / 'windows' / 'app.py').write_text('new', encoding='utf-8')
            updater.install_files(staged, support)
            self.assertTrue((support / 'update-backup').is_dir())
            updater.finish_update(support)
            self.assertFalse((support / 'update-backup').exists())

    def test_wait_for_exit_detects_a_finished_process(self):
        process = subprocess.Popen([sys.executable, '-c', 'pass'])
        process.wait()
        self.assertTrue(updater.wait_for_exit(process.pid, timeout=2))

    def test_version_and_build_are_set(self):
        self.assertRegex(common.VERSION, r'^\d+\.\d+\.\d+$')
        self.assertGreaterEqual(common.BUILD, 1)


if __name__ == '__main__': unittest.main()

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
            with urllib.request.urlopen(base + '/health') as r: self.assertEqual(json.load(r)['app'], 'Prisma')
            data = json.dumps({'text':'Hola'}).encode()
            with self.assertRaises(urllib.error.HTTPError) as e: urllib.request.urlopen(urllib.request.Request(base + '/speak', data=data))
            self.assertEqual(e.exception.code, 401)
            request = urllib.request.Request(base + '/speak', data=data, headers={'X-Prisma-Token':'secret'})
            with urllib.request.urlopen(request) as r: self.assertTrue(json.load(r)['ok'])
            self.assertEqual(server.events.get_nowait(), ('speak', {'text':'Hola'}))
        finally: server.shutdown(); server.server_close(); thread.join()


class InstallTests(unittest.TestCase):
    def test_preserves_hooks_and_idempotence(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(install, 'SUPPORT', Path(directory) / 'Prisma'):
            p = Path(directory) / 'hooks.json'
            p.write_text(json.dumps({'other': 42, 'hooks': {'Stop': [{'hooks': [{'type':'command','command':'other'}]}]}}), encoding='utf-8')
            install.hooks(p); install.hooks(p)
            data = json.loads(p.read_text(encoding='utf-8'))
            self.assertEqual(data['other'], 42)
            self.assertEqual(len(data['hooks']['Stop']), 2)
            self.assertEqual(data['hooks']['Stop'][0]['hooks'][0]['command'], 'other')
            self.assertEqual(len(data['hooks']['PreToolUse']), 1)

if __name__ == '__main__': unittest.main()

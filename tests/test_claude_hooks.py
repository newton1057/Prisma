import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / 'plugin' / 'scripts' / 'on_stop.sh'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('jq'), 'macOS hook scripts; jq is required')
class ClaudeHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        support = home / 'Library' / 'Application Support' / 'Prisma'
        support.mkdir(parents=True)
        (support / 'runtime.json').write_text(json.dumps({'port': 8787, 'token': 'test-token'}))
        bin_dir = home / 'bin'
        bin_dir.mkdir()
        curl = bin_dir / 'curl'
        curl.write_text('''#!/bin/bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--data-binary" ]; then
    printf '%s\\n' "$2" | jq -c . >> "$PRISMA_TEST_PAYLOADS"
    exit 0
  fi
  shift
done
printf '%s' '{"app":"Prisma"}'
''')
        curl.chmod(0o755)
        self.payloads = home / 'payloads.jsonl'
        self.env = dict(os.environ, HOME=str(home), PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        PRISMA_TEST_PAYLOADS=str(self.payloads))

    def run_hook(self, event):
        result = subprocess.run(['bash', str(HOOK)], input=json.dumps(event), text=True,
                                capture_output=True, env=self.env, check=True)
        self.assertEqual(json.loads(result.stdout), {})

    def messages(self):
        if not self.payloads.exists():
            return []
        return [json.loads(line) for line in self.payloads.read_text().splitlines()]

    def test_claude_question_is_registered_and_announced_once(self):
        config = json.loads((ROOT / 'plugin' / 'hooks' / 'hooks.json').read_text())['hooks']
        self.assertTrue(any(re.fullmatch(entry['matcher'], 'AskUserQuestion')
                            for entry in config['PreToolUse']))
        self.assertIn('PermissionRequest', config)
        event = {'hook_event_name': 'PreToolUse', 'tool_name': 'AskUserQuestion',
                 'session_id': 'claude-session', 'tool_input': {'questions': [
                     {'question': '¿Qué prefieres?', 'options': [
                         {'label': 'Primera'}, {'label': 'Segunda (Recommended)'}]}]}}
        self.run_hook(event)
        self.run_hook(dict(event, hook_event_name='PermissionRequest'))
        messages = self.messages()
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0]['text'], '¿Qué prefieres? Opciones: Primera, Segunda.')
        self.assertEqual(messages[0]['source'], 'claude-code')

    def test_claude_reply_reaches_the_orb_of_its_window(self):
        transcript = Path(self.temp.name) / 'claude.jsonl'
        line = {'type': 'assistant', 'message': {'role': 'assistant', 'content': [
            {'type': 'text', 'text': 'Hecho.\n\n<ForPrisma>\nListo, terminé.\n</ForPrisma>'}]}}
        transcript.write_text(json.dumps(line, separators=(',', ':')) + '\n')
        self.run_hook({'hook_event_name': 'Stop', 'session_id': 'claude-session',
                       'transcript_path': str(transcript)})
        message = self.messages()[0]
        self.assertEqual(message['text'], 'Listo, terminé.')
        self.assertEqual(message['source'], 'claude-code')
        self.assertIsInstance(message['pid'], int)

    def test_claude_permission_and_unrelated_tool(self):
        self.run_hook({'hook_event_name': 'PreToolUse', 'tool_name': 'Read'})
        self.assertEqual(self.messages(), [])
        self.run_hook({'hook_event_name': 'PermissionRequest', 'tool_name': 'Bash',
                       'session_id': 'claude-session', 'tool_input': {}})
        self.assertEqual(self.messages()[0]['text'], '¿Me permites ejecutar este comando en la terminal?')


if __name__ == '__main__':
    unittest.main()

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FAKE_CURL = '''#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    http://*/session/start|http://*/session/end|http://*/thinking|http://*/interrupt) printf '%s\\n' "$arg" >> "$HOME/endpoints" ;;
    '{'*) printf '%s\\n' "$arg" | jq -c . >> "$HOME/payloads" ;;
  esac
done
'''


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('jq'), 'macOS hook scripts; jq is required')
class ThinkingHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        support = self.home / 'Library/Application Support/Prisma'
        support.mkdir(parents=True)
        (support / 'runtime.json').write_text(json.dumps({'port': 8787, 'token': 'test'}))
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        curl = bin_dir / 'curl'
        curl.write_text(FAKE_CURL)
        curl.chmod(0o755)
        self.env = dict(os.environ, HOME=self.temp.name, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'])

    def run_turn(self, event, *args):
        result = subprocess.run(['bash', str(ROOT / 'plugin/scripts/on_turn.sh'), *args],
                                input=json.dumps(event), text=True, capture_output=True,
                                env=self.env, check=True)
        self.assertEqual(json.loads(result.stdout), {})

    def endpoints(self):
        path = self.home / 'endpoints'
        return [line.split('8787/')[1] for line in path.read_text().splitlines()] if path.exists() else []

    def payloads(self):
        path = self.home / 'payloads'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_claude_session_has_its_own_waiting_orb(self):
        config = json.loads((ROOT / 'plugin/hooks/hooks.json').read_text())['hooks']
        for event in ('SessionStart', 'UserPromptSubmit', 'StopFailure', 'SessionEnd'):
            self.assertTrue(config[event][0]['hooks'][0]['command'].endswith('on_turn.sh" claude-code'))

        transcript = self.home / 'claude.jsonl'
        transcript.write_text('{"type":"user"}\n')
        for event in ('SessionStart', 'UserPromptSubmit', 'StopFailure', 'SessionEnd'):
            self.run_turn({'hook_event_name': event, 'session_id': 'claude-session',
                           'transcript_path': str(transcript), 'source': 'startup'}, 'claude-code')
        self.assertEqual(self.endpoints(), ['session/start', 'thinking', 'interrupt', 'session/end'])
        start, thinking, interrupt, end = self.payloads()
        for payload in (start, thinking, interrupt, end):
            self.assertEqual(payload['session_id'], 'claude-session')
            self.assertEqual(payload['source'], 'claude-code')
        # The window's process travels with the start of a session or a turn.
        self.assertIsInstance(start['pid'], int)
        self.assertEqual(thinking['pid'], start['pid'])
        self.assertNotIn('pid', interrupt)
        # Claude Code has no interrupt hook: Prisma watches the transcript while thinking.
        self.assertEqual(thinking['transcript_path'], str(transcript))
        self.assertNotIn('transcript_path', start)

    def test_older_claude_hooks_without_argument_are_recognised(self):
        transcript = self.home / 'claude.jsonl'
        transcript.write_text('{"type":"user"}\n')
        self.run_turn({'hook_event_name': 'UserPromptSubmit', 'session_id': 'claude-session',
                       'transcript_path': str(transcript)})
        self.assertEqual(self.endpoints(), ['thinking'])
        self.assertEqual(self.payloads()[0]['source'], 'claude-code')

    def test_opencode_sends_its_session_folder(self):
        for event in ('SessionStart', 'UserPromptSubmit', 'Interrupt'):
            self.run_turn({'hook_event_name': event, 'session_id': 'ses_1', 'directory': '/tmp/project'}, 'opencode')
        self.assertEqual(self.endpoints(), ['session/start', 'thinking', 'interrupt'])
        for payload in self.payloads():
            self.assertEqual(payload, {'session_id': 'ses_1', 'source': 'opencode', 'directory': '/tmp/project'})

    def test_codex_session_lifecycle_preserves_identity(self):
        for event in ('SessionStart', 'UserPromptSubmit', 'Interrupt', 'SessionEnd'):
            self.run_turn({'hook_event_name': event, 'session_id': 'codex-session'}, 'codex')
        self.assertEqual(self.endpoints(), ['session/start', 'thinking', 'interrupt', 'session/end'])
        for payload in self.payloads():
            self.assertEqual(payload, {'session_id': 'codex-session', 'source': 'codex'})
        # A Codex transcript identifies Codex even through an older or shared hook.
        transcript = self.home / 'codex.jsonl'
        transcript.write_text('{"type":"session_meta"}\n')
        self.run_turn({'hook_event_name': 'UserPromptSubmit', 'session_id': 'codex-session',
                       'transcript_path': str(transcript)}, 'claude-code')
        self.assertEqual(self.payloads()[-1], {'session_id': 'codex-session', 'source': 'codex'})

    def test_unknown_agents_keep_the_single_orb(self):
        self.run_turn({'hook_event_name': 'SessionStart', 'session_id': 'other'})
        self.run_turn({'hook_event_name': 'SessionEnd', 'session_id': 'other'})
        self.assertEqual(self.endpoints(), ['interrupt'])


if __name__ == '__main__':
    unittest.main()

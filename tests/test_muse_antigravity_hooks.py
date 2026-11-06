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
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-binary) printf '%s\\n' "$2" | jq -c . >> "$HOME/payloads"; exit 0 ;;
    http://*/session/start|http://*/session/end|http://*/thinking|http://*/interrupt|http://*/speak) printf '%s\\n' "$1" >> "$HOME/endpoints" ;;
  esac
  shift
done
printf '%s' '{"app":"Prisma"}'
'''

AGY_BASE = {
    'artifactDirectoryPath': '/tmp/art',
    'conversationId': 'a3ef078f-bfd4-485e-ad1a-6df1ec263083',
    'modelName': 'gemini-3.8-flash-high',
    'transcriptPath': '/tmp/transcript_full.jsonl',
    'workspacePaths': ['/tmp/agyproj'],
}


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('jq'), 'macOS hook scripts; jq is required')
class MuseAntigravityHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        support = self.home / 'Library/Application Support/Prisma'
        support.mkdir(parents=True)
        (support / 'runtime.json').write_text(json.dumps({'port': 8787, 'token': 'test'}))
        shutil.copy2(ROOT / 'plugin/scripts/on_turn.sh', support / 'on_turn.sh')
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

    def run_stop(self, event, *args):
        result = subprocess.run(['bash', str(ROOT / 'plugin/scripts/on_stop.sh'), *args],
                                input=json.dumps(event), text=True, capture_output=True,
                                env=self.env, check=True)
        return json.loads(result.stdout)

    def endpoints(self):
        path = self.home / 'endpoints'
        return [line.split('8787/')[1] for line in path.read_text().splitlines()] if path.exists() else []

    def payloads(self):
        path = self.home / 'payloads'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    # MARK: Muse Code

    def test_muse_session_lifecycle(self):
        for event in ('SessionStart', 'UserPromptSubmit', 'Interrupt', 'StopFailure', 'SessionEnd'):
            self.run_turn({'hook_event_name': event, 'session_id': '01a1-muse',
                           'cwd': '/tmp/proj'}, 'muse')
        self.assertEqual(self.endpoints(), ['session/start', 'thinking', 'interrupt', 'interrupt', 'session/end'])
        for payload in self.payloads():
            self.assertEqual(payload['session_id'], '01a1-muse')
            self.assertEqual(payload['source'], 'muse')
            self.assertEqual(payload['directory'], '/tmp/proj')
        self.assertIsInstance(self.payloads()[0]['pid'], int)

    def test_muse_stop_speaks_the_forprisma_block(self):
        result = self.run_stop({
            'hook_event_name': 'Stop',
            'last_assistant_message': 'Trabajo listo.\n\n<ForPrisma>\nTerminé la tarea.\n</ForPrisma>',
            'session_id': '01a1-muse',
            'cwd': '/tmp/proj',
        }, 'muse')
        self.assertEqual(result, {})
        message = self.payloads()[0]
        self.assertEqual(message['text'], 'Terminé la tarea.')
        self.assertEqual(message['source'], 'muse')

    def test_muse_question_keeps_its_source(self):
        self.run_stop({'hook_event_name': 'PreToolUse', 'tool_name': 'request_user_input',
                       'session_id': '01a1-muse', 'tool_input': {'questions': [
                           {'question': '¿Qué hago?', 'options': [{'label': 'Seguir'}]}]}}, 'muse')
        message = self.payloads()[0]
        self.assertEqual(message['text'], '¿Qué hago? Opciones: Seguir.')
        self.assertEqual(message['source'], 'muse')

    # MARK: Antigravity

    def test_antigravity_session_events(self):
        self.run_turn(dict(AGY_BASE), 'antigravity', 'SessionStart')
        self.run_turn(dict(AGY_BASE, invocationNum=0, initialNumSteps=1), 'antigravity', 'PreInvocation')
        self.assertEqual(self.endpoints(), ['session/start', 'thinking'])
        for payload in self.payloads():
            self.assertEqual(payload['session_id'], AGY_BASE['conversationId'])
            self.assertEqual(payload['source'], 'antigravity')
            self.assertEqual(payload['directory'], '/tmp/agyproj')
        self.assertIsInstance(self.payloads()[0]['pid'], int)

    def test_antigravity_stop_reads_the_transcript(self):
        transcript = self.home / 'transcript_full.jsonl'
        lines = [
            {'step_index': 0, 'source': 'USER_EXPLICIT', 'type': 'USER_INPUT', 'content': 'hazlo'},
            {'step_index': 1, 'source': 'MODEL', 'type': 'PLANNER_RESPONSE', 'content': 'trabajando'},
            {'step_index': 2, 'source': 'MODEL', 'type': 'GENERIC', 'content': 'A1: done'},
            {'step_index': 3, 'source': 'MODEL', 'type': 'PLANNER_RESPONSE',
             'content': 'Listo.\n<ForPrisma>\nQuedó arreglado.\n</ForPrisma>'},
        ]
        transcript.write_text('\n'.join(json.dumps(line) for line in lines) + '\n')
        result = self.run_stop(dict(AGY_BASE, transcriptPath=str(transcript),
                                    terminationReason='NO_TOOL_CALL', error=''), 'antigravity', 'Stop')
        self.assertEqual(result, {})
        self.assertEqual(self.payloads()[0]['text'], 'Quedó arreglado.')

    def test_antigravity_stop_with_an_error_stays_silent(self):
        missing = self.home / 'missing.jsonl'
        result = self.run_stop(dict(AGY_BASE, transcriptPath=str(missing),
                                    terminationReason='error', error='boom'),
                               'antigravity', 'Stop')
        self.assertEqual(result, {})
        self.assertEqual([p for p in self.payloads() if 'text' in p], [])
        # The turn still ends: Prisma clears the thinking orb through on_turn.
        self.assertEqual(self.endpoints(), ['interrupt'])

    def test_antigravity_stop_does_not_repeat_an_older_reply(self):
        transcript = self.home / 'pending.jsonl'
        lines = [
            {'step_index': 0, 'source': 'MODEL', 'type': 'PLANNER_RESPONSE', 'content': 'Del turno anterior.'},
            {'step_index': 1, 'source': 'MODEL', 'type': 'PLANNER_RESPONSE', 'content': None},
        ]
        transcript.write_text('\n'.join(json.dumps(line) for line in lines) + '\n')
        result = self.run_stop(dict(AGY_BASE, transcriptPath=str(transcript),
                                    terminationReason='NO_TOOL_CALL', error=''), 'antigravity', 'Stop')
        self.assertEqual(result, {})
        self.assertEqual([p for p in self.payloads() if 'text' in p], [])
        self.assertEqual(self.endpoints(), ['interrupt'])

    def test_antigravity_question_and_permission_answer_allow(self):
        question = dict(AGY_BASE)
        question['toolCall'] = {'name': 'ask_question', 'args': {'questions': [
            {'question': '¿Qué color prefieres?', 'options': ['(Recommended) Rojo', 'Azul']}]}}
        result = self.run_stop(question, 'antigravity', 'PreToolUse')
        self.assertEqual(result, {'decision': 'allow'})
        self.assertEqual(self.payloads()[0]['text'], '¿Qué color prefieres? Opciones: Rojo, Azul.')

        permission = dict(AGY_BASE)
        permission['toolCall'] = {'name': 'ask_permission', 'args': {
            'Action': 'read', 'Target': '/etc/hosts', 'Reason': 'Necesito leer la red'}}
        result = self.run_stop(permission, 'antigravity', 'PreToolUse')
        self.assertEqual(result, {'decision': 'allow'})
        self.assertEqual(self.payloads()[1]['text'], 'Necesito leer la red')

    def test_antigravity_unrelated_tool_is_allowed_without_speech(self):
        other = dict(AGY_BASE)
        other['toolCall'] = {'name': 'run_command', 'args': {'CommandLine': 'ls'}}
        result = self.run_stop(other, 'antigravity', 'PreToolUse')
        self.assertEqual(result, {'decision': 'allow'})
        self.assertEqual(self.payloads(), [])


if __name__ == '__main__':
    unittest.main()

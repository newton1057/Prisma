"""Non-blocking agent hook. Always emits an empty JSON result.

Usage: hook.py [source] [event]
  source: codex | claude | opencode | muse | antigravity (optional; the
          payload usually identifies the agent)
  event:  for agent payloads without a hook_event_name (Antigravity): Stop,
          PreToolUse.
"""
import json
import sys
import time
from pathlib import Path
from common import SUPPORT, question_text, send, speech_text, transcript_text

QUESTION_TOOLS = (
    'AskUserQuestion', 'request_user_input', 'request_user_input_async',
    'send_user_message_async', 'send_message_to_user_async', 'question',
    'ask_question', 'ask_permission',
)


def normalize(data, source, event):
    """Antigravity sends camelCase fields and no hook_event_name."""
    if source == 'antigravity' or data.get('conversationId'):
        tool = data.get('toolCall') or {}
        args = tool.get('args') or {}
        workspaces = data.get('workspacePaths') or []
        return {
            'hook_event_name': event or 'Stop',
            'session_id': data.get('conversationId', ''),
            'transcript_path': data.get('transcriptPath', ''),
            'cwd': workspaces[0] if workspaces else '',
            'tool_name': tool.get('name', ''),
            'tool_input': args,
            'source': 'antigravity',
            'error': data.get('error', ''),
        }
    if source:
        data['source'] = data.get('source') or source
    return data


def main(data, source='', event=''):
    data = normalize(data, source, event)
    event = data.get('hook_event_name', event or 'Stop')
    if event not in ('Stop', 'PreToolUse', 'PermissionRequest'): return
    if event == 'Stop' and data.get('error'): return
    tool = data.get('tool_name', '')
    if event == 'PreToolUse' and tool not in QUESTION_TOOLS: return
    text = data.get('last_assistant_message') or ''
    if event in ('PreToolUse', 'PermissionRequest'):
        inputs = data.get('tool_input') or {}
        text = question_text(inputs)
        if not text and tool == 'ask_permission':
            if isinstance(inputs, str):
                try: inputs = json.loads(inputs)
                except ValueError: inputs = {}
            if isinstance(inputs, dict):
                text = inputs.get('Reason') or inputs.get('reason') or ''
            text = text or '¿Me permites continuar con esta acción?'
        if not text and event == 'PermissionRequest':
            if isinstance(inputs, str):
                try: inputs = json.loads(inputs)
                except ValueError: inputs = {}
            if isinstance(inputs, dict): text = inputs.get('description') or inputs.get('justification') or inputs.get('reason') or ''
            text = text or '¿Me permites continuar con esta acción?'
    if not text and data.get('transcript_path') and not (data.get('source') == 'antigravity' and event == 'PreToolUse'):
        text = transcript_text(data['transcript_path'])
    text = speech_text(text)
    if not text: return
    SUPPORT.mkdir(parents=True, exist_ok=True)
    cache = SUPPORT / 'last_spoken.json'
    signature = str(data.get('session_id') or '') + '|' + text
    try:
        previous = json.loads(cache.read_text(encoding='utf-8'))
        if previous.get('signature') == signature and time.time() - previous.get('timestamp', 0) < 45: return
    except (OSError, ValueError, TypeError): pass
    cache.write_text(json.dumps({'signature': signature, 'timestamp': time.time()}), encoding='utf-8')
    send({'text': text, 'session_id': data.get('session_id', ''), 'cwd': data.get('cwd', ''), 'source': data.get('source', 'agent')})


if __name__ == '__main__':
    try:
        if hasattr(sys.stdin, 'reconfigure'): sys.stdin.reconfigure(encoding='utf-8')
        source = sys.argv[1] if len(sys.argv) > 1 else ''
        event = sys.argv[2] if len(sys.argv) > 2 else ''
        main(json.load(sys.stdin), source, event)
    except Exception as exc:
        try:
            SUPPORT.mkdir(parents=True, exist_ok=True)
            with (SUPPORT / 'hook.log').open('a', encoding='utf-8') as f: f.write(f'{time.ctime()} {exc}\n')
        except OSError: pass
    print('{}')

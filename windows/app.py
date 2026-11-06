"""Prisma for Windows: tray application, overlay, speech and loopback server."""
import ctypes
import hmac
import json
import logging
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import tkinter as tk
from tkinter import ttk
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import agents
from common import SUPPORT, RUNTIME, VERSION, BUILD, runtime, speech_text
from orb import THEME_TITLES
from overlay import OrbOverlay
import updater

SUPPORT.mkdir(parents=True, exist_ok=True)
logging.basicConfig(filename=SUPPORT / 'prisma.log', level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
SETTINGS_PATH = SUPPORT / 'settings.json'
VOICES = {'ava': 'en-US-AvaMultilingualNeural', 'andrew': 'en-US-AndrewMultilingualNeural', 'emma': 'en-US-EmmaMultilingualNeural', 'brian': 'en-US-BrianMultilingualNeural', 'dalia': 'es-MX-DaliaNeural', 'jorge': 'es-MX-JorgeNeural', 'salome': 'es-CO-SalomeNeural', 'ximena': 'es-ES-XimenaNeural', 'alvaro': 'es-ES-AlvaroNeural', 'elena': 'es-AR-ElenaNeural'}
DEFAULTS = {'engine': 'edge', 'voice': 'ava', 'mode': 'full', 'speed': 1.0, 'position': 'top', 'theme': 'prisma', 'stayVisible': True, 'duckAudio': True, 'duckLevel': .35}
THEME_KEYS = {title: key for key, title in THEME_TITLES.items()}
MODEL = SUPPORT / 'voices' / 'es_MX-claude-high.onnx'
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
# Updates only replace a copy that lives in the support folder; a checkout
# launched from the repository is for development.
INSTALLED = Path(__file__).resolve().parent == SUPPORT.resolve()
RELEASES = 'https://github.com/newton1057/Prisma/releases'


def load_settings():
    try:
        settings = json.loads(SETTINGS_PATH.read_text(encoding='utf-8'))
        return {**DEFAULTS, **settings} if isinstance(settings, dict) else DEFAULTS.copy()
    except (OSError, ValueError): return DEFAULTS.copy()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def reply(self, code, obj):
        raw = json.dumps(obj).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def do_GET(self):
        if self.path.split('?')[0] == '/health': self.reply(200, {'ok': True, 'app': 'Prisma', 'version': VERSION, 'build': BUILD})
        else: self.reply(404, {'ok': False})
    def do_POST(self):
        auth = self.headers.get('X-Prisma-Token', self.headers.get('X-CodexVoz-Token', ''))
        if not auth and self.headers.get('Authorization', '').startswith('Bearer '): auth = self.headers['Authorization'][7:]
        if not hmac.compare_digest(auth, self.server.token):
            self.reply(401, {'ok': False, 'error': 'unauthorized'}); return
        if self.path.split('?')[0] == '/stop':
            self.server.events.put(('stop', None)); self.reply(200, {'ok': True}); return
        if self.path.split('?')[0] != '/speak':
            self.reply(404, {'ok': False}); return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 1000000: raise ValueError()
            obj = json.loads(self.rfile.read(length))
            if not isinstance(obj, dict) or not isinstance(obj.get('text'), str) or not obj['text'].strip(): raise ValueError()
        except (ValueError, UnicodeDecodeError):
            self.reply(400, {'ok': False, 'error': 'invalid body'}); return
        self.server.events.put(('speak', obj)); self.reply(200, {'ok': True})


class Ducker:
    """Reduce other audio sessions, restoring only values unchanged by the user."""
    def __init__(self): self.sessions = []
    def duck(self, level):
        try:
            import comtypes
            from pycaw.pycaw import AudioUtilities
            comtypes.CoInitialize()
            self.initialized = True
            for session in AudioUtilities.GetAllSessions():
                if session.ProcessId == os.getpid(): continue
                try:
                    volume = session.SimpleAudioVolume
                    original = volume.GetMasterVolume()
                    target = original * max(0.0, min(1.0, float(level)))
                    volume.SetMasterVolume(target, None)
                    self.sessions.append((volume, original, target))
                except Exception: logging.exception('No se pudo atenuar una sesión')
        except Exception: logging.exception('No se pudo atenuar el audio')
    def restore(self):
        for volume, original, target in self.sessions:
            try:
                if abs(volume.GetMasterVolume() - target) < .01: volume.SetMasterVolume(original, None)
            except Exception: logging.exception('No se pudo restaurar una sesión')
        self.sessions.clear()
        if getattr(self, 'initialized', False):
            import comtypes
            comtypes.CoUninitialize()
            self.initialized = False


class Speech:
    def __init__(self, events):
        self.events = events
        self.cancel = None
        self.thread = None
        self.serial = 0
    def stop(self):
        if self.cancel: self.cancel.set()
        if self.thread and self.thread.is_alive(): self.thread.join(timeout=4)
        self.serial += 1
    def speak(self, payload, settings):
        self.stop()
        self.cancel = threading.Event()
        serial = self.serial
        self.thread = threading.Thread(target=self.run, args=(payload, settings.copy(), self.cancel, serial), daemon=True)
        self.thread.start()
    def run_process(self, args, cancel, input_text=None):
        proc = subprocess.Popen(args, stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=NO_WINDOW, env={**os.environ, 'PYTHONUTF8': '1'})
        if input_text is not None:
            try: proc.stdin.write(input_text.encode('utf-8')); proc.stdin.close()
            except (BrokenPipeError, OSError): pass
        while proc.poll() is None:
            if cancel.wait(.05):
                proc.kill(); proc.wait(); return False
        return proc.returncode == 0
    def run(self, payload, settings, cancel, serial):
        text = speech_text(payload['text'])
        if settings['mode'] == 'notice': text = 'Prisma terminó de trabajar.'
        elif settings['mode'] == 'short': text = text[:320]
        else: text = text[:6000]
        if not text: return
        engine = (payload.get('engine') or settings['engine']).lower()
        voice = payload.get('voice') or settings['voice']
        if engine in VOICES: voice, engine = engine, 'edge'
        if voice in ('edge', 'piper', 'windows'): engine = voice
        voice = VOICES.get(str(voice).lower(), voice)
        speed = max(.8, min(1.2, float(settings['speed'])))
        engines = {'edge': ['edge', 'piper', 'windows'], 'piper': ['piper', 'windows'], 'windows': ['windows']}.get(engine, ['windows'])
        self.events.put(('show', serial))
        try:
            for backend in engines:
                if cancel.is_set(): break
                try:
                    if self.play_backend(backend, text, voice, speed, settings, cancel): break
                except Exception: logging.exception('Falló el motor %s', backend)
        finally: self.events.put(('hide', serial))
    def play_backend(self, backend, text, voice, speed, settings, cancel):
        ducker = Ducker()
        try:
            if backend == 'windows':
                if settings['duckAudio']: ducker.duck(max(.65, float(settings['duckLevel'])))
                rate = round((speed - 1) * 10)
                script = '[Console]::InputEncoding=[Text.Encoding]::UTF8; Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Rate=' + str(rate) + '; $s.Speak([Console]::In.ReadToEnd())'
                return self.run_process(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script], cancel, text)
            if backend == 'piper' and not MODEL.exists(): return False
            with tempfile.TemporaryDirectory(prefix='prisma-') as tmp:
                output = str(Path(tmp) / ('voice.mp3' if backend == 'edge' else 'voice.wav'))
                if backend == 'edge':
                    args = [sys.executable, '-m', 'edge_tts', '--voice', str(voice), f'--rate={round((speed-1)*100):+d}%', '--text', text, '--write-media', output]
                    ok = self.run_process(args, cancel)
                else:
                    args = [sys.executable, '-m', 'piper', '--model', str(MODEL), '--output_file', output, '--length_scale', str(1/speed)]
                    ok = self.run_process(args, cancel, text)
                if not ok or cancel.is_set(): return False
                import pygame
                if not pygame.mixer.get_init(): pygame.mixer.init()
                pygame.mixer.music.load(output)
                if settings['duckAudio']: ducker.duck(settings['duckLevel'])
                pygame.mixer.music.play()
                while pygame.mixer.music.get_busy() and not cancel.wait(.05): pass
                pygame.mixer.music.stop()
                pygame.mixer.music.unload()
                return not cancel.is_set()
        finally: ducker.restore()


class App:
    def __init__(self):
        self.root = tk.Tk(); self.root.withdraw()
        self.events = queue.Queue(); self.settings = load_settings(); self.speech = Speech(self.events)
        self.agent_busy = None; self.agent_overrides = {}; self.agent_warnings = []
        self.update_state = 'idle'; self.update_manifest = None; self.update_detail = ''
        self.update_progress = 0; self.update_thread = None; self.updating = False
        self.update_notified = None
        self.overlay = OrbOverlay(self.settings.get('theme', 'prisma'), self.settings['position'])
        try: self.overlay.start()
        except Exception: logging.exception('No se pudo iniciar el orbe')
        self.server = None
        import secrets
        token = secrets.token_urlsafe(32)
        for port in range(8787, 8799):
            try: self.server = Server(('127.0.0.1', port), Handler); break
            except OSError: pass
        if not self.server: raise RuntimeError('No hay puertos libres para Prisma')
        self.server.token = token; self.server.events = self.events
        RUNTIME.write_text(json.dumps({'port': port, 'token': token, 'pid': os.getpid()}), encoding='utf-8')
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.tray(); self.root.after(50, self.poll)
        self.root.after(5000, self.auto_update_check)
    def tray(self):
        import pystray
        from PIL import Image, ImageDraw
        img = Image.new('RGBA', (64, 64)); d = ImageDraw.Draw(img)
        d.ellipse((4, 4, 60, 60), fill='#4b40b9', outline='#a6e8ff', width=3)
        d.ellipse((15, 15, 49, 49), fill='#53a4dd')
        self.icon = pystray.Icon('Prisma', img, 'Prisma', self.tray_menu()); self.icon.run_detached()
    def tray_menu(self):
        import pystray
        if self.update_state == 'available' and self.update_manifest:
            update = pystray.MenuItem(f'Actualizar a la versión {self.update_manifest.version}…', lambda icon, item: self.events.put(('update-install', None)))
        elif self.update_state in ('checking', 'downloading', 'installing'):
            text = 'Buscando actualizaciones…' if self.update_state == 'checking' else 'Actualizando Prisma…'
            update = pystray.MenuItem(text, lambda icon, item: None, enabled=False)
        else:
            update = pystray.MenuItem('Buscar actualizaciones…', lambda icon, item: self.events.put(('update-check', True)))
        return pystray.Menu(
            pystray.MenuItem('Probar voz', lambda icon, item: self.events.put(('speak', {'text': 'Hola. Prisma está funcionando en Windows.'}))),
            pystray.MenuItem('Ajustes', lambda icon, item: self.events.put(('settings', None)), default=True),
            update,
            pystray.MenuItem('Detener voz', lambda icon, item: self.events.put(('stop', None))),
            pystray.MenuItem('Salir', lambda icon, item: self.events.put(('quit', None))),
        )
    def refresh_tray_menu(self):
        if not hasattr(self, 'icon'): return
        try:
            self.icon.menu = self.tray_menu(); self.icon.update_menu()
        except Exception: logging.exception('No se pudo actualizar el menú de la bandeja')
    def notify(self, title, message):
        try: self.icon.notify(message, title)
        except Exception: logging.debug('No se pudo mostrar la notificación', exc_info=True)
    def poll(self):
        try:
            while True:
                action, data = self.events.get_nowait()
                if action == 'speak': self.speech.speak(data, self.settings)
                elif action == 'stop': self.speech.stop(); self.overlay.hide(immediate=True)
                elif action == 'show' and data == self.speech.serial: self.show_overlay()
                elif action == 'hide' and data == self.speech.serial: self.root.after(1200 if self.settings['stayVisible'] else 200, lambda s=data: self.hide_overlay() if s == self.speech.serial else None)
                elif action == 'settings': self.show_settings()
                elif action == 'agent-done': self.agent_finished(*data)
                elif action == 'update-check': self.check_updates(manual=True)
                elif action == 'update-install': self.install_update()
                elif action == 'update-progress': self.update_progress_changed(data)
                elif action == 'update-status': self.update_status(data)
                elif action == 'update-install-now': self.close(); return
                elif action == 'quit': self.close(); return
        except queue.Empty: pass
        self.root.after(50, self.poll)
    def show_overlay(self):
        self.overlay.show(speaking=True)
    def hide_overlay(self):
        self.overlay.set_speaking(False)
        self.overlay.hide()
    def show_settings(self):
        if hasattr(self, 'dialog') and self.dialog.winfo_exists(): self.dialog.lift(); return
        self.dialog = tk.Toplevel(self.root); self.dialog.title('Prisma — Ajustes'); self.dialog.resizable(False, False)
        outer = ttk.Frame(self.dialog, padding=18); outer.grid()
        box = ttk.LabelFrame(outer, text='Agentes', padding=10); box.grid(row=0, columnspan=2, sticky='ew', pady=(0, 14))
        self.agent_rows = ttk.Frame(box); self.agent_rows.grid(row=0, sticky='ew')
        self.agent_note = ttk.Label(box, text='Solo sesiones locales en este PC: las sesiones en la nube o en otro equipo no ejecutan estos hooks.', wraplength=440, justify='left', foreground='#666')
        self.agent_note.grid(row=1, sticky='w', pady=(8, 0))
        self.agent_status = ttk.Label(box, text='', wraplength=440, justify='left')
        self.agent_status.grid(row=2, sticky='w', pady=(4, 0))
        updates = ttk.LabelFrame(outer, text='Actualizaciones', padding=10); updates.grid(row=1, columnspan=2, sticky='ew', pady=(0, 14))
        self.update_box = ttk.Frame(updates); self.update_box.grid(sticky='ew')
        frame = ttk.Frame(outer); frame.grid(row=2, columnspan=2, sticky='ew'); fields = {}
        options = [('Motor', 'engine', ['edge', 'piper', 'windows']), ('Voz Edge', 'voice', list(VOICES)), ('Lectura', 'mode', ['full', 'short', 'notice']), ('Posición', 'position', ['top', 'bottom', 'center', 'corner']), ('Color del halo', 'theme', list(THEME_TITLES.values()))]
        theme = self.settings.get('theme', 'prisma')
        for row, (label, key, values) in enumerate(options):
            ttk.Label(frame, text=label).grid(row=row, column=0, sticky='w', pady=4)
            current = THEME_TITLES.get(theme, THEME_TITLES['prisma']) if key == 'theme' else self.settings[key]
            fields[key] = tk.StringVar(value=current); ttk.Combobox(frame, textvariable=fields[key], values=values, state='readonly', width=25).grid(row=row, column=1)
        for row, (label, key, start, end) in enumerate([('Velocidad', 'speed', .8, 1.2), ('Nivel audio de fondo', 'duckLevel', 0, 1)], 5):
            ttk.Label(frame, text=label).grid(row=row, column=0, sticky='w', pady=4)
            fields[key] = tk.DoubleVar(value=self.settings[key]); ttk.Scale(frame, from_=start, to=end, variable=fields[key]).grid(row=row, column=1, sticky='ew')
        for row, (label, key) in enumerate([('Atenuar otras aplicaciones', 'duckAudio'), ('Mantener visible al terminar', 'stayVisible')], 7):
            fields[key] = tk.BooleanVar(value=self.settings[key]); ttk.Checkbutton(frame, text=label, variable=fields[key]).grid(row=row, columnspan=2, sticky='w', pady=4)
        def save():
            values = {key: value.get() for key, value in fields.items()}
            values['theme'] = THEME_KEYS.get(values['theme'], 'prisma')
            self.settings.update(values); SETTINGS_PATH.write_text(json.dumps(self.settings, indent=2), encoding='utf-8')
            self.overlay.set_theme(self.settings['theme']); self.overlay.set_position(self.settings['position'])
            self.dialog.destroy()
        ttk.Button(frame, text='Guardar', command=save).grid(row=9, columnspan=2, pady=(12,0))
        ttk.Label(outer, text=f'Prisma {VERSION} (build {BUILD})', foreground='#777').grid(row=3, columnspan=2, pady=(10, 0))
        self.refresh_agents(); self.refresh_updates()
    def refresh_agents(self):
        if not (hasattr(self, 'agent_rows') and self.agent_rows.winfo_exists()): return
        for child in self.agent_rows.winfo_children(): child.destroy()
        try: infos = agents.statuses()
        except Exception:
            logging.exception('No se pudieron comprobar los agentes')
            infos = [agents.AgentInfo(key, agents.TITLES[key], 'failed', 'No se pudo comprobar') for key in agents.TITLES]
        colors = {'connected': '#1f9d55', 'incomplete': '#c47b00', 'disconnected': '#8a8a8a', 'missing': '#b0b0b0', 'working': '#2d7dd2', 'failed': '#c0392b'}
        overrides = getattr(self, 'agent_overrides', {})
        for row, info in enumerate(infos):
            state, detail = overrides.get(info.key, (info.state, info.detail))
            tk.Label(self.agent_rows, text='●', fg=colors.get(state, '#8a8a8a'), font=('Segoe UI', 13)).grid(row=row, column=0, sticky='w', padx=(0, 8), pady=3)
            text = ttk.Frame(self.agent_rows); text.grid(row=row, column=1, sticky='w')
            ttk.Label(text, text=info.title).grid(sticky='w')
            ttk.Label(text, text=detail, foreground='#666').grid(sticky='w')
            actions = ttk.Frame(self.agent_rows); actions.grid(row=row, column=2, sticky='e', padx=(14, 0))
            busy = getattr(self, 'agent_busy', None)
            if state == 'working' or busy:
                ttk.Label(actions, text='…').grid()
            elif state == 'connected':
                ttk.Button(actions, text='Reconectar', command=lambda kind=info.key: self.agent_action(kind, 'connect')).grid(row=0, column=0, padx=(0, 4))
                ttk.Button(actions, text='Desconectar', command=lambda kind=info.key: self.agent_action(kind, 'disconnect')).grid(row=0, column=1)
            elif state == 'missing':
                ttk.Label(actions, text='Instala su CLI para conectarlo', foreground='#777').grid()
            else:
                ttk.Button(actions, text='Conectar', command=lambda kind=info.key: self.agent_action(kind, 'connect')).grid()
        self.agent_rows.columnconfigure(1, weight=1)
        warnings = getattr(self, 'agent_warnings', [])
        if warnings:
            self.agent_status.configure(text='\n'.join(warnings), foreground='#a15c00')
        else:
            self.agent_status.configure(text='Conecta Prisma con cada agente desde aquí. Instala sus hooks e instrucciones en tu carpeta de usuario; reinicia las sesiones abiertas para que tomen los cambios.', foreground='#666')
    def agent_action(self, kind, action):
        if getattr(self, 'agent_busy', None): return
        self.agent_busy = kind
        self.agent_warnings = []
        self.agent_overrides = dict(getattr(self, 'agent_overrides', {}))
        self.agent_overrides[kind] = ('working', 'Conectando…' if action == 'connect' else 'Desconectando…')
        self.refresh_agents()
        threading.Thread(target=self.agent_worker, args=(kind, action), daemon=True).start()
    def agent_worker(self, kind, action):
        try:
            warnings = agents.connect(kind) if action == 'connect' else (agents.disconnect(kind) or [])
            self.events.put(('agent-done', (kind, warnings, '')))
        except Exception as error:
            logging.exception('No se pudo configurar %s', kind)
            self.events.put(('agent-done', (kind, [], str(error))))
    def agent_finished(self, kind, warnings, error):
        self.agent_busy = None
        self.agent_overrides = {key: value for key, value in getattr(self, 'agent_overrides', {}).items() if key != kind}
        self.agent_warnings = ([f'No se pudo configurar {agents.TITLES[kind]}: {error}'] if error else list(warnings))
        self.refresh_agents()
    def auto_update_check(self):
        self.check_updates(manual=False)
        self.root.after(6 * 60 * 60 * 1000, self.auto_update_check)
    def check_updates(self, manual=False):
        if self.updating or (self.update_thread and self.update_thread.is_alive()): return
        if not INSTALLED:
            if manual:
                self.update_state = 'failed'
                self.update_detail = 'Las actualizaciones solo funcionan en la app instalada.'
                self.refresh_updates(); self.refresh_tray_menu()
            return
        if manual:
            self.update_state = 'checking'; self.update_detail = ''
            self.refresh_updates(); self.refresh_tray_menu()
        def worker():
            try:
                manifest = updater.check(BUILD)
            except Exception as error:
                logging.exception('No se pudo comprobar la actualización')
                detail = str(error) if isinstance(error, updater.UpdateError) else f'No se pudo comprobar si hay versiones nuevas: {error}'
                self.events.put(('update-status', {'state': 'failed', 'detail': detail, 'manifest': None, 'manual': manual}))
                return
            if manifest:
                payload = {'state': 'available', 'detail': '', 'manifest': manifest, 'manual': manual}
            elif manual:
                payload = {'state': 'uptodate', 'detail': '', 'manifest': None, 'manual': manual}
            else:
                payload = {'state': 'idle', 'detail': '', 'manifest': None, 'manual': manual}
            self.events.put(('update-status', payload))
        self.update_thread = threading.Thread(target=worker, daemon=True); self.update_thread.start()
    def update_progress_changed(self, percent):
        if self.update_state != 'downloading': return
        self.update_progress = max(0, min(100, int(percent)))
        self.refresh_updates()
    def update_status(self, data):
        state = data.get('state', 'idle'); manifest = data.get('manifest'); detail = data.get('detail', '')
        manual = bool(data.get('manual')); previous = self.update_state
        # A check finishing late must not overwrite download progress.
        if previous in ('downloading', 'installing') and state not in ('failed', 'installing'): return
        if state == 'failed' and not manual and previous in ('idle', 'available', 'uptodate'):
            self.update_thread = None
            logging.info('Comprobación de actualización fallida: %s', detail)
            return
        self.update_thread = None
        self.update_state = state
        self.update_manifest = manifest if state in ('available', 'downloading', 'installing', 'failed') else None
        self.update_detail = detail
        if state != 'downloading': self.update_progress = 0
        if state == 'failed': self.updating = False
        self.refresh_updates(); self.refresh_tray_menu()
        if state == 'available' and manifest:
            if self.update_notified != manifest.build:
                self.update_notified = manifest.build
                self.notify(f'Versión {manifest.version} disponible', 'Abre Ajustes para actualizar Prisma.')
        elif state == 'uptodate':
            self.notify('Prisma está al día', f'Tienes la versión {VERSION}.')
        elif state == 'failed' and manual:
            self.notify('No se completó la actualización', detail or 'Inténtalo de nuevo desde Ajustes.')
    def install_update(self):
        manifest = self.update_manifest
        if manifest is None:
            self.check_updates(manual=True); return
        if self.updating: return
        if not INSTALLED:
            self.update_state = 'failed'; self.update_detail = 'Las actualizaciones solo funcionan en la app instalada.'
            self.refresh_updates(); self.refresh_tray_menu(); return
        if self.speech.thread and self.speech.thread.is_alive():
            self.update_state = 'failed'; self.update_detail = 'Espera a que Prisma termine de hablar.'
            self.refresh_updates(); self.refresh_tray_menu(); return
        self.updating = True
        self.update_state = 'downloading'; self.update_detail = ''; self.update_progress = 0
        self.refresh_updates(); self.refresh_tray_menu()
        def worker():
            workspace = Path(tempfile.mkdtemp(prefix='prisma-update-'))
            package = workspace / 'actualizacion.zip'
            last = [-1]
            def progress(fraction):
                percent = int(round(fraction * 100))
                if percent != last[0]:
                    last[0] = percent
                    self.events.put(('update-progress', percent))
            try:
                updater.download(manifest, package, progress=progress)
                staged = updater.prepare(package, manifest, workspace)
                updater.launch_helper(staged, SUPPORT, os.getpid(), workspace)
            except Exception as error:
                logging.exception('No se pudo preparar la actualización')
                shutil.rmtree(workspace, ignore_errors=True)
                detail = str(error) if isinstance(error, updater.UpdateError) else f'No se pudo actualizar: {error}'
                self.events.put(('update-status', {'state': 'failed', 'detail': detail, 'manifest': manifest, 'manual': True}))
                return
            self.events.put(('update-status', {'state': 'installing', 'detail': '', 'manifest': manifest, 'manual': True}))
            self.events.put(('update-install-now', None))
        self.update_thread = threading.Thread(target=worker, daemon=True); self.update_thread.start()
    def refresh_updates(self):
        try:
            if not self.update_box.winfo_exists(): return
        except (AttributeError, tk.TclError):
            return
        for child in self.update_box.winfo_children(): child.destroy()
        box = self.update_box; state = self.update_state; manifest = self.update_manifest
        ttk.Label(box, text=f'Prisma {VERSION} (build {BUILD})', font=('Segoe UI', 10, 'bold')).grid(row=0, column=0, sticky='w')
        if state == 'checking':
            text = 'Buscando actualizaciones…'
        elif state == 'uptodate':
            text = 'Prisma está al día.'
        elif state == 'available' and manifest:
            text = f'Versión {manifest.version} disponible.'
            if manifest.notes.strip(): text += '\n\n' + manifest.notes.strip()[:1500]
        elif state == 'downloading' and manifest:
            text = f'Descargando la versión {manifest.version}… {self.update_progress} %'
        elif state == 'installing' and manifest:
            text = f'Instalando la versión {manifest.version}. Prisma se reiniciará en unos segundos.'
        elif state == 'failed':
            text = self.update_detail or 'No se completó la actualización.'
        else:
            text = 'Comprueba si hay una versión nueva firmada.'
        ttk.Label(box, text=text, wraplength=460, justify='left', foreground='#555').grid(row=1, column=0, sticky='w', pady=(6, 8))
        actions = ttk.Frame(box); actions.grid(row=2, column=0, sticky='w')
        busy = state in ('checking', 'downloading', 'installing') or self.updating
        check = ttk.Button(actions, text='Buscar actualizaciones', command=lambda: self.check_updates(manual=True))
        check.grid(row=0, column=0, padx=(0, 6)); check.state(['disabled'] if busy else ['!disabled'])
        column = 1
        if state == 'available' and manifest:
            update = ttk.Button(actions, text=f'Actualizar a la versión {manifest.version}', command=self.install_update)
            update.grid(row=0, column=column, padx=(0, 6)); update.state(['disabled'] if busy else ['!disabled'])
            column += 1
        elif state == 'failed' and manifest:
            retry = ttk.Button(actions, text='Reintentar', command=self.install_update)
            retry.grid(row=0, column=column, padx=(0, 6)); retry.state(['disabled'] if self.updating else ['!disabled'])
            column += 1
        if state in ('available', 'failed'):
            ttk.Button(actions, text='Descargar de GitHub', command=lambda: webbrowser.open(RELEASES)).grid(row=0, column=column)
        if not INSTALLED:
            ttk.Label(box, text='Las actualizaciones solo funcionan en la app instalada.', foreground='#777').grid(row=3, column=0, sticky='w', pady=(6, 0))
    def close(self):
        self.speech.stop(); self.overlay.stop(); self.server.shutdown(); self.server.server_close(); self.icon.stop()
        try:
            if json.loads(RUNTIME.read_text(encoding='utf-8')).get('pid') == os.getpid(): RUNTIME.unlink()
        except (OSError, ValueError): pass
        self.root.destroy()


if __name__ == '__main__':
    # A mutex prevents simultaneous agent hooks from starting two tray apps.
    mutex = ctypes.windll.kernel32.CreateMutexW(None, False, 'Local\\PrismaSingleInstance')
    if not mutex: raise ctypes.WinError()
    if ctypes.windll.kernel32.GetLastError() == 183: sys.exit(0)
    if runtime(): sys.exit(0)
    try:
        app = App(); app.root.mainloop()
    except Exception:
        logging.exception('Prisma no pudo iniciar')
        raise

"""Prisma for Windows: tray application, overlay, speech and loopback server."""
import ctypes
import hmac
import json
import logging
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import tkinter as tk
from tkinter import ttk
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from common import SUPPORT, RUNTIME, runtime, speech_text

SUPPORT.mkdir(parents=True, exist_ok=True)
logging.basicConfig(filename=SUPPORT / 'prisma.log', level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
SETTINGS_PATH = SUPPORT / 'settings.json'
VOICES = {'ava': 'en-US-AvaMultilingualNeural', 'andrew': 'en-US-AndrewMultilingualNeural', 'emma': 'en-US-EmmaMultilingualNeural', 'brian': 'en-US-BrianMultilingualNeural', 'dalia': 'es-MX-DaliaNeural', 'jorge': 'es-MX-JorgeNeural', 'salome': 'es-CO-SalomeNeural', 'ximena': 'es-ES-XimenaNeural', 'alvaro': 'es-ES-AlvaroNeural', 'elena': 'es-AR-ElenaNeural'}
DEFAULTS = {'engine': 'edge', 'voice': 'ava', 'mode': 'full', 'speed': 1.0, 'position': 'top', 'stayVisible': True, 'duckAudio': True, 'duckLevel': .35}
MODEL = SUPPORT / 'voices' / 'es_MX-claude-high.onnx'
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


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
        if self.path.split('?')[0] == '/health': self.reply(200, {'ok': True, 'app': 'Prisma', 'version': '1.0'})
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
        self.overlay = tk.Toplevel(self.root); self.overlay.withdraw(); self.overlay.overrideredirect(True); self.overlay.attributes('-topmost', True)
        self.overlay.configure(bg='#010101'); self.overlay.attributes('-transparentcolor', '#010101')
        self.canvas = tk.Canvas(self.overlay, width=180, height=180, bg='#010101', highlightthickness=0); self.canvas.pack()
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
        self.tray(); self.root.after(50, self.poll); self.root.after(60, self.animate)
    def tray(self):
        import pystray
        from PIL import Image, ImageDraw
        img = Image.new('RGBA', (64, 64)); d = ImageDraw.Draw(img)
        d.ellipse((4, 4, 60, 60), fill='#4b40b9', outline='#a6e8ff', width=3)
        d.ellipse((15, 15, 49, 49), fill='#53a4dd')
        menu = pystray.Menu(pystray.MenuItem('Probar voz', lambda icon, item: self.events.put(('speak', {'text': 'Hola. Prisma está funcionando en Windows.'}))), pystray.MenuItem('Ajustes', lambda icon, item: self.events.put(('settings', None)), default=True), pystray.MenuItem('Detener voz', lambda icon, item: self.events.put(('stop', None))), pystray.MenuItem('Salir', lambda icon, item: self.events.put(('quit', None))))
        self.icon = pystray.Icon('Prisma', img, 'Prisma', menu); self.icon.run_detached()
    def poll(self):
        try:
            while True:
                action, data = self.events.get_nowait()
                if action == 'speak': self.speech.speak(data, self.settings)
                elif action == 'stop': self.speech.stop(); self.overlay.withdraw()
                elif action == 'show' and data == self.speech.serial: self.show_overlay()
                elif action == 'hide' and data == self.speech.serial: self.root.after(1200 if self.settings['stayVisible'] else 200, lambda s=data: self.overlay.withdraw() if s == self.speech.serial else None)
                elif action == 'settings': self.show_settings()
                elif action == 'quit': self.close(); return
        except queue.Empty: pass
        self.root.after(50, self.poll)
    def show_overlay(self):
        w = self.root.winfo_screenwidth(); h = self.root.winfo_screenheight(); pos = self.settings['position']
        x, y = (w-180)//2, 25
        if pos == 'bottom': y = h-220
        elif pos == 'center': y = (h-180)//2
        elif pos == 'corner': x, y = w-200, h-220
        self.overlay.geometry(f'180x180+{max(0,x)}+{max(0,y)}'); self.overlay.deiconify()
        self.overlay.update_idletasks()
        try:
            hwnd = ctypes.windll.user32.GetParent(self.overlay.winfo_id())
            style = ctypes.windll.user32.GetWindowLongW(hwnd, -20)
            ctypes.windll.user32.SetWindowLongW(hwnd, -20, style | 0x20 | 0x80 | 0x08000000)
        except Exception: logging.exception('No se pudo configurar la ventana flotante')
    def animate(self):
        import math
        self.canvas.delete('all'); t = time.monotonic(); pulse = 3 * math.sin(t * 5)
        for i, color in enumerate(('#25334e', '#423f94', '#5b68d2', '#6fc4e4', '#c5e9ed')):
            r = 70 - i * 10 + pulse
            self.canvas.create_oval(90-r, 90-r, 90+r, 90+r, fill=color, outline='')
        self.root.after(60, self.animate)
    def show_settings(self):
        if hasattr(self, 'dialog') and self.dialog.winfo_exists(): self.dialog.lift(); return
        self.dialog = tk.Toplevel(self.root); self.dialog.title('Prisma — Ajustes'); self.dialog.resizable(False, False)
        frame = ttk.Frame(self.dialog, padding=18); frame.grid(); fields = {}
        options = [('Motor', 'engine', ['edge', 'piper', 'windows']), ('Voz Edge', 'voice', list(VOICES)), ('Lectura', 'mode', ['full', 'short', 'notice']), ('Posición', 'position', ['top', 'bottom', 'center', 'corner'])]
        for row, (label, key, values) in enumerate(options):
            ttk.Label(frame, text=label).grid(row=row, column=0, sticky='w', pady=4)
            fields[key] = tk.StringVar(value=self.settings[key]); ttk.Combobox(frame, textvariable=fields[key], values=values, state='readonly', width=25).grid(row=row, column=1)
        for row, (label, key, start, end) in enumerate([('Velocidad', 'speed', .8, 1.2), ('Nivel audio de fondo', 'duckLevel', 0, 1)], 4):
            ttk.Label(frame, text=label).grid(row=row, column=0, sticky='w', pady=4)
            fields[key] = tk.DoubleVar(value=self.settings[key]); ttk.Scale(frame, from_=start, to=end, variable=fields[key]).grid(row=row, column=1, sticky='ew')
        for row, (label, key) in enumerate([('Atenuar otras aplicaciones', 'duckAudio'), ('Mantener visible al terminar', 'stayVisible')], 6):
            fields[key] = tk.BooleanVar(value=self.settings[key]); ttk.Checkbutton(frame, text=label, variable=fields[key]).grid(row=row, columnspan=2, sticky='w', pady=4)
        def save():
            self.settings.update({key: value.get() for key, value in fields.items()}); SETTINGS_PATH.write_text(json.dumps(self.settings, indent=2), encoding='utf-8'); self.dialog.destroy()
        ttk.Button(frame, text='Guardar', command=save).grid(row=8, columnspan=2, pady=(12,0))
    def close(self):
        self.speech.stop(); self.server.shutdown(); self.server.server_close(); self.icon.stop()
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

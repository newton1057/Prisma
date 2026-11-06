"""Per-pixel-alpha orb overlay for Windows.

Tk cannot draw the translucent, antialiased orb: a transparent colour key
leaves a grey square when the key and the window background disagree.  This
module creates a ``WS_EX_LAYERED`` popup and paints the Pillow frame with
``UpdateLayeredWindow`` so every pixel keeps its own alpha.

The Win32 libraries are loaded lazily in the worker thread, which keeps this
module importable on macOS for the portable tests.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import logging
import os
import queue
import threading
import time

from PIL import Image, ImageChops

import orb

DISPLAY = 180
FRAME_INTERVAL = 1 / 30
INTRO = 0.22
OUTRO = 0.16
TOP_MARGIN = 25
BOTTOM_MARGIN = 40
SIDE_MARGIN = 20


def placement(position: str, screen_width: int, screen_height: int, size: int = DISPLAY) -> tuple[int, int]:
    """Top-left corner for one of the four positions used by Ajustes."""
    x, y = (screen_width - size) // 2, TOP_MARGIN
    if position == 'bottom':
        y = screen_height - size - BOTTOM_MARGIN
    elif position == 'center':
        y = (screen_height - size) // 2
    elif position == 'corner':
        x, y = screen_width - size - SIDE_MARGIN, screen_height - size - BOTTOM_MARGIN
    return max(0, x), max(0, y)


def premultiplied_bgra(image: Image.Image) -> bytes:
    """Windows expects premultiplied BGRA for ``AC_SRC_ALPHA``."""
    image = image.convert('RGBA')
    red, green, blue, alpha = image.split()
    red = ImageChops.multiply(red, alpha)
    green = ImageChops.multiply(green, alpha)
    blue = ImageChops.multiply(blue, alpha)
    return Image.merge('RGBA', (red, green, blue, alpha)).tobytes('raw', 'BGRA')


def scaled(image: Image.Image, factor: float) -> Image.Image:
    """Scale the orb around the canvas centre, keeping the canvas size."""
    if abs(factor - 1) < 0.005:
        return image
    width = max(1, round(image.width * factor))
    height = max(1, round(image.height * factor))
    resized = image.resize((width, height), Image.Resampling.LANCZOS)
    result = Image.new('RGBA', image.size, (0, 0, 0, 0))
    result.alpha_composite(resized, ((image.width - width) // 2, (image.height - height) // 2))
    return result


def with_alpha(image: Image.Image, factor: float) -> Image.Image:
    if factor >= 0.999:
        return image
    result = image.copy()
    result.putalpha(image.getchannel('A').point(lambda value: round(value * max(0.0, factor))))
    return result


class _Message(ctypes.Structure):
    _fields_ = [
        ('hwnd', wintypes.HWND),
        ('message', wintypes.UINT),
        ('wParam', wintypes.WPARAM),
        ('lParam', wintypes.LPARAM),
        ('time', wintypes.DWORD),
        ('pt', wintypes.POINT),
    ]


class _BitmapInfoHeader(ctypes.Structure):
    _fields_ = [
        ('biSize', wintypes.DWORD),
        ('biWidth', wintypes.LONG),
        ('biHeight', wintypes.LONG),
        ('biPlanes', wintypes.WORD),
        ('biBitCount', wintypes.WORD),
        ('biCompression', wintypes.DWORD),
        ('biSizeImage', wintypes.DWORD),
        ('biXPelsPerMeter', wintypes.LONG),
        ('biYPelsPerMeter', wintypes.LONG),
        ('biClrUsed', wintypes.DWORD),
        ('biClrImportant', wintypes.DWORD),
    ]


class _RgbQuad(ctypes.Structure):
    _fields_ = [
        ('rgbBlue', wintypes.BYTE),
        ('rgbGreen', wintypes.BYTE),
        ('rgbRed', wintypes.BYTE),
        ('rgbReserved', wintypes.BYTE),
    ]


class _BitmapInfo(ctypes.Structure):
    _fields_ = [('bmiHeader', _BitmapInfoHeader), ('bmiColors', _RgbQuad * 1)]


class _BlendFunction(ctypes.Structure):
    _fields_ = [
        ('BlendOp', wintypes.BYTE),
        ('BlendFlags', wintypes.BYTE),
        ('SourceConstantAlpha', wintypes.BYTE),
        ('AlphaFormat', wintypes.BYTE),
    ]


class _Worker(threading.Thread):
    """Owns the layered window and its animation loop in one thread."""

    WS_EX_LAYERED = 0x00080000
    WS_EX_TRANSPARENT = 0x00000020
    WS_EX_TOPMOST = 0x00000008
    WS_EX_TOOLWINDOW = 0x00000080
    WS_EX_NOACTIVATE = 0x08000000
    WS_POPUP = 0x80000000
    SW_HIDE = 0
    SW_SHOWNOACTIVATE = 4
    HWND_TOPMOST = -1
    SWP_NOSIZE = 0x0001
    SWP_NOMOVE = 0x0002
    SWP_NOACTIVATE = 0x0010
    GWL_EXSTYLE = -20
    ULW_ALPHA = 2
    AC_SRC_OVER = 0
    AC_SRC_ALPHA = 1
    DIB_RGB_COLORS = 0
    PM_REMOVE = 0x0001
    WM_DESTROY = 0x0010
    WM_ERASEBKGND = 0x0014
    WM_NCHITTEST = 0x0084
    HTTRANSPARENT = -1
    IDC_ARROW = 32512
    ERROR_CLASS_ALREADY_EXISTS = 1410

    def __init__(self, commands: queue.Queue, theme: str, position: str):
        super().__init__(name='PrismaOrb', daemon=True)
        self.commands = commands
        self.theme = theme
        self.position = position
        self.running = True
        self.visibility = 0.0
        self.target = 0.0
        self.origin = (0, 0)
        self.animator = orb.OrbAnimator(theme)
        self.hwnd = None
        self._shown = False
        self._next_frame = 0.0
        self._memory_dc = None
        self._bitmap = None
        self._bits = ctypes.c_void_p()
        self._wndproc_ref = None
        self._user32 = None
        self._gdi32 = None
        self._kernel32 = None

    # -- Win32 setup --------------------------------------------------------

    def _load(self):
        self._user32 = ctypes.WinDLL('user32', use_last_error=True)
        self._gdi32 = ctypes.WinDLL('gdi32', use_last_error=True)
        self._kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

        user32, gdi32, kernel32 = self._user32, self._gdi32, self._kernel32

        self._WNDPROC = ctypes.WINFUNCTYPE(
            ctypes.c_ssize_t, wintypes.HWND, wintypes.UINT,
            ctypes.c_size_t, ctypes.c_ssize_t,
        )
        self._WNDCLASSW = type('WNDCLASSW', (ctypes.Structure,), {
            '_fields_': [
                ('style', wintypes.UINT),
                ('lpfnWndProc', self._WNDPROC),
                ('cbClsExtra', ctypes.c_int),
                ('cbWndExtra', ctypes.c_int),
                ('hInstance', wintypes.HINSTANCE),
                ('hIcon', wintypes.HICON),
                ('hCursor', wintypes.HANDLE),
                ('hbrBackground', wintypes.HBRUSH),
                ('lpszMenuName', wintypes.LPCWSTR),
                ('lpszClassName', wintypes.LPCWSTR),
            ],
        })

        user32.CreateWindowExW.argtypes = [
            wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
            ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID,
        ]
        user32.CreateWindowExW.restype = wintypes.HWND
        user32.RegisterClassW.argtypes = [ctypes.POINTER(self._WNDCLASSW)]
        user32.RegisterClassW.restype = wintypes.ATOM
        user32.DefWindowProcW.argtypes = [
            wintypes.HWND, wintypes.UINT, ctypes.c_size_t, ctypes.c_ssize_t,
        ]
        user32.DefWindowProcW.restype = ctypes.c_ssize_t
        user32.LoadCursorW.argtypes = [wintypes.HINSTANCE, ctypes.c_void_p]
        user32.LoadCursorW.restype = wintypes.HANDLE
        user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
        user32.ShowWindow.restype = wintypes.BOOL
        user32.SetWindowPos.argtypes = [
            wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
            ctypes.c_int, ctypes.c_int, wintypes.UINT,
        ]
        user32.SetWindowPos.restype = wintypes.BOOL
        user32.GetDC.argtypes = [wintypes.HWND]
        user32.GetDC.restype = wintypes.HDC
        user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
        user32.ReleaseDC.restype = ctypes.c_int
        user32.UpdateLayeredWindow.argtypes = [
            wintypes.HWND, wintypes.HDC, ctypes.POINTER(wintypes.POINT),
            ctypes.POINTER(wintypes.SIZE), wintypes.HDC,
            ctypes.POINTER(wintypes.POINT), wintypes.DWORD,
            ctypes.POINTER(_BlendFunction), wintypes.DWORD,
        ]
        user32.UpdateLayeredWindow.restype = wintypes.BOOL
        user32.PeekMessageW.argtypes = [
            ctypes.POINTER(_Message), wintypes.HWND, wintypes.UINT,
            wintypes.UINT, wintypes.UINT,
        ]
        user32.PeekMessageW.restype = wintypes.BOOL
        user32.TranslateMessage.argtypes = [ctypes.POINTER(_Message)]
        user32.DispatchMessageW.argtypes = [ctypes.POINTER(_Message)]
        user32.DispatchMessageW.restype = ctypes.c_ssize_t
        user32.DestroyWindow.argtypes = [wintypes.HWND]
        user32.DestroyWindow.restype = wintypes.BOOL
        user32.GetSystemMetrics.argtypes = [ctypes.c_int]
        user32.GetSystemMetrics.restype = ctypes.c_int

        gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
        gdi32.CreateCompatibleDC.restype = wintypes.HDC
        gdi32.CreateDIBSection.argtypes = [
            wintypes.HDC, ctypes.POINTER(_BitmapInfo), wintypes.UINT,
            ctypes.POINTER(ctypes.c_void_p), wintypes.HANDLE, wintypes.DWORD,
        ]
        gdi32.CreateDIBSection.restype = wintypes.HBITMAP
        gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
        gdi32.SelectObject.restype = wintypes.HGDIOBJ
        gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
        gdi32.DeleteObject.restype = wintypes.BOOL
        gdi32.DeleteDC.argtypes = [wintypes.HDC]
        gdi32.DeleteDC.restype = wintypes.BOOL

        kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
        kernel32.GetModuleHandleW.restype = wintypes.HINSTANCE

    def _wndproc(self, hwnd, message, wparam, lparam):
        try:
            if message == self.WM_DESTROY:
                self.hwnd = None
                return 0
            if message == self.WM_ERASEBKGND:
                return 1
            if message == self.WM_NCHITTEST:
                return self.HTTRANSPARENT
            return self._user32.DefWindowProcW(hwnd, message, wparam, lparam)
        except Exception:
            logging.exception('Fallo en el procedimiento de ventana del orbe')
            return 0

    def _create_window(self):
        self._load()
        user32, gdi32, kernel32 = self._user32, self._gdi32, self._kernel32
        instance = kernel32.GetModuleHandleW(None)
        self._wndproc_ref = self._WNDPROC(self._wndproc)
        window_class = self._WNDCLASSW()
        window_class.style = 0
        window_class.lpfnWndProc = self._wndproc_ref
        window_class.hInstance = instance
        window_class.hCursor = user32.LoadCursorW(None, self.IDC_ARROW)
        window_class.lpszClassName = 'PrismaOrbOverlay'
        if not user32.RegisterClassW(ctypes.byref(window_class)):
            error = ctypes.get_last_error()
            if error != self.ERROR_CLASS_ALREADY_EXISTS:
                raise ctypes.WinError(error)

        style = (self.WS_EX_LAYERED | self.WS_EX_TRANSPARENT | self.WS_EX_TOPMOST
                 | self.WS_EX_TOOLWINDOW | self.WS_EX_NOACTIVATE)
        self.hwnd = user32.CreateWindowExW(
            style, 'PrismaOrbOverlay', 'Prisma', self.WS_POPUP,
            0, 0, DISPLAY, DISPLAY, None, None, instance, None,
        )
        if not self.hwnd:
            raise ctypes.WinError(ctypes.get_last_error())
        user32.SetWindowPos(
            self.hwnd, wintypes.HWND(self.HWND_TOPMOST),
            0, 0, 0, 0, self.SWP_NOMOVE | self.SWP_NOSIZE | self.SWP_NOACTIVATE,
        )

        header = _BitmapInfoHeader()
        header.biSize = ctypes.sizeof(_BitmapInfoHeader)
        header.biWidth = DISPLAY
        header.biHeight = -DISPLAY
        header.biPlanes = 1
        header.biBitCount = 32
        header.biCompression = self.DIB_RGB_COLORS
        info = _BitmapInfo()
        info.bmiHeader = header
        self._memory_dc = gdi32.CreateCompatibleDC(None)
        self._bitmap = gdi32.CreateDIBSection(
            self._memory_dc, ctypes.byref(info), self.DIB_RGB_COLORS,
            ctypes.byref(self._bits), None, 0,
        )
        if not self._bitmap:
            raise ctypes.WinError(ctypes.get_last_error())
        gdi32.SelectObject(self._memory_dc, self._bitmap)

    def _close_window(self):
        if self.hwnd:
            self._user32.ShowWindow(self.hwnd, self.SW_HIDE)
            self._user32.DestroyWindow(self.hwnd)
            self.hwnd = None
        if self._bitmap:
            self._gdi32.DeleteObject(self._bitmap)
            self._bitmap = None
        if self._memory_dc:
            self._gdi32.DeleteDC(self._memory_dc)
            self._memory_dc = None

    # -- painting -----------------------------------------------------------

    def _update_origin(self):
        width = self._user32.GetSystemMetrics(0)
        height = self._user32.GetSystemMetrics(1)
        self.origin = placement(self.position, width, height)

    def _show(self):
        self._update_origin()
        self._user32.SetWindowPos(
            self.hwnd, wintypes.HWND(self.HWND_TOPMOST),
            self.origin[0], self.origin[1], 0, 0,
            self.SWP_NOSIZE | self.SWP_NOACTIVATE,
        )
        self._user32.ShowWindow(self.hwnd, self.SW_SHOWNOACTIVATE)
        self._shown = True

    def _hide(self):
        if self.hwnd:
            self._user32.ShowWindow(self.hwnd, self.SW_HIDE)
        self._shown = False

    def _paint(self, image: Image.Image, alpha: float):
        factor = DISPLAY / image.width
        frame = scaled(image, factor)
        frame = scaled(frame, 0.90 + 0.10 * alpha)
        frame = with_alpha(frame, alpha)
        data = premultiplied_bgra(frame)
        ctypes.memmove(self._bits, data, len(data))
        screen = self._user32.GetDC(None)
        try:
            destination = wintypes.POINT(*self.origin)
            size = wintypes.SIZE(DISPLAY, DISPLAY)
            source = wintypes.POINT(0, 0)
            blend = _BlendFunction(self.AC_SRC_OVER, 0, 255, self.AC_SRC_ALPHA)
            ok = self._user32.UpdateLayeredWindow(
                self.hwnd, screen, ctypes.byref(destination), ctypes.byref(size),
                self._memory_dc, ctypes.byref(source), 0, ctypes.byref(blend),
                self.ULW_ALPHA,
            )
            if not ok:
                logging.error('UpdateLayeredWindow falló: %s', ctypes.get_last_error())
        finally:
            self._user32.ReleaseDC(None, screen)

    # -- commands and loop --------------------------------------------------

    def _handle(self, action, value):
        if action == 'show':
            self.animator.set_speaking(bool(value))
            self.target = 1.0
            if not self._shown:
                self._show()
        elif action == 'hide':
            self.animator.set_speaking(False)
            self.target = 0.0
            if value:
                self.visibility = 0.0
        elif action == 'speaking':
            self.animator.set_speaking(bool(value))
        elif action == 'theme':
            if value in orb.PALETTES:
                self.theme = value
                self.animator.theme = value
                orb.renderer(value)
        elif action == 'position':
            self.position = value
            if self._shown:
                self._show()
        elif action == 'stop':
            self.running = False

    def _pump(self):
        message = _Message()
        while self._user32.PeekMessageW(ctypes.byref(message), None, 0, 0, self.PM_REMOVE):
            self._user32.TranslateMessage(ctypes.byref(message))
            self._user32.DispatchMessageW(ctypes.byref(message))

    def run(self):
        try:
            self._create_window()
        except Exception:
            logging.exception('No se pudo crear la ventana del orbe')
            self._close_window()
            return
        try:
            orb.renderer(self.theme).render(orb.OrbFrame(time=0, voice=0, idle=1, theme=self.theme))
        except Exception:
            logging.exception('No se pudo preparar el orbe')
        previous = time.monotonic()
        try:
            while self.running:
                while True:
                    try:
                        action, value = self.commands.get_nowait()
                    except queue.Empty:
                        break
                    self._handle(action, value)
                if not self.running:
                    break
                self._pump()
                now = time.monotonic()
                delta = min(max(0.0, now - previous), 0.1)
                previous = now
                if self.visibility < self.target:
                    self.visibility = min(self.target, self.visibility + delta / INTRO)
                elif self.visibility > self.target:
                    self.visibility = max(self.target, self.visibility - delta / OUTRO)
                if self.visibility > 0.001 or self._shown:
                    if now >= self._next_frame:
                        eased = self.visibility * self.visibility * (3 - 2 * self.visibility)
                        image = orb.frame_image(self.animator.frame(now))
                        self._paint(image, eased)
                        self._next_frame = now + FRAME_INTERVAL
                        if self.visibility <= 0.001 and self.target <= 0.001:
                            self._hide()
                    delay = min(0.02, max(0.001, self._next_frame - time.monotonic()))
                else:
                    delay = 0.02
                self._pump()
                time.sleep(delay)
        except Exception:
            logging.exception('El orbe dejó de animarse')
        finally:
            self._close_window()


class OrbOverlay:
    """Thread-safe facade used by the Tk app."""

    def __init__(self, theme: str = 'prisma', position: str = 'top'):
        self.theme = theme if theme in orb.PALETTES else 'prisma'
        self.position = position
        self._commands = queue.Queue()
        self._worker = None
        self._lock = threading.Lock()

    def start(self):
        if self._worker or os.name != 'nt':
            return
        with self._lock:
            if self._worker:
                return
            self._worker = _Worker(self._commands, self.theme, self.position)
            self._worker.start()

    def _send(self, action, value=None):
        self._commands.put((action, value))

    def show(self, speaking: bool = True):
        self._send('show', speaking)

    def hide(self, immediate: bool = False):
        self._send('hide', immediate)

    def set_speaking(self, speaking: bool):
        self._send('speaking', speaking)

    def set_theme(self, theme: str):
        if theme not in orb.PALETTES:
            theme = 'prisma'
        self.theme = theme
        self._send('theme', theme)

    def set_position(self, position: str):
        self.position = position
        self._send('position', position)

    def stop(self):
        worker = self._worker
        if not worker:
            return
        self._send('stop')
        worker.join(timeout=2)
        self._worker = None

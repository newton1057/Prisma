"""Signed updates for Prisma for Windows.

Mirrors ``app/Sources/Prisma/Updater.swift``: the bucket publishes a manifest
signed with the same Ed25519 key as macOS, and nothing replaces the runtime
before its size, SHA-256, version and build match. The signature is verified
with a small RFC 8032 implementation so the app needs no compiled crypto
dependency.

The app downloads and prepares the package, then launches ``update_helper.py``
with pythonw. Windows cannot replace modules that the running app still has
open, so the helper waits for the tray app to exit, copies the verified files
and opens Prisma again. Settings, the virtual environment and the voice model
live beside the code and are left untouched.
"""
from __future__ import annotations

import base64
import binascii
from contextlib import nullcontext
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import quote
import urllib.request
import zipfile

MANIFEST_NAME = 'windows-latest.json'
DEFAULT_BASE = 'https://storage.googleapis.com/prisma-updates'
# The same key as UpdateChannel.publicKey on macOS.
PUBLIC_KEY = 'SmrHvQbhETtIohDL39YXcMSQOunV7vP1aYAFWmg+QKo='
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
TIMEOUT = 30
MAX_MANIFEST = 1 << 20
MAX_PACKAGE = 200 * 1024 * 1024
MAX_UNPACKED = 300 * 1024 * 1024
RUNTIME_SUFFIXES = ('.py',)


class UpdateError(Exception):
    """A problem that can be shown to the user as-is, in Spanish."""


@dataclass(frozen=True)
class Manifest:
    version: str
    build: int
    file: str
    size: int
    sha256: str
    notes: str
    signature: str

    @classmethod
    def from_json(cls, raw) -> 'Manifest':
        try:
            data = json.loads(raw)
        except (TypeError, ValueError) as error:
            raise UpdateError('El servidor de actualizaciones no devolvió un manifiesto válido.') from error
        if not isinstance(data, dict):
            raise UpdateError('El servidor de actualizaciones no devolvió un manifiesto válido.')

        def text(name: str) -> str:
            value = data.get(name)
            if not isinstance(value, str):
                raise UpdateError(f'El manifiesto de actualizaciones no incluye {name}.')
            return value

        version = text('version')
        file = text('file')
        sha256 = text('sha256')
        notes = text('notes')
        signature = text('signature')
        build = data.get('build')
        size = data.get('size')
        if type(build) is not int or build < 1:
            raise UpdateError('El manifiesto de actualizaciones tiene un build inválido.')
        if type(size) is not int or not 0 < size <= MAX_PACKAGE:
            raise UpdateError('El manifiesto de actualizaciones tiene un tamaño inválido.')
        if not re.fullmatch(r'[0-9A-Za-z._+-]+', version):
            raise UpdateError('El manifiesto de actualizaciones tiene una versión inválida.')
        if not _safe_member(file):
            raise UpdateError('El manifiesto de actualizaciones apunta a una ruta no permitida.')
        if not re.fullmatch(r'[0-9a-fA-F]{64}', sha256):
            raise UpdateError('El manifiesto de actualizaciones tiene un SHA-256 inválido.')
        try:
            raw_signature = base64.b64decode(signature, validate=True)
        except (binascii.Error, ValueError) as error:
            raise UpdateError('La firma del manifiesto no es válida.') from error
        if len(raw_signature) != 64:
            raise UpdateError('La firma del manifiesto no es válida.')
        return cls(version, build, file, size, sha256.lower(), notes, signature)

    def signed_text(self) -> str:
        # Same order as UpdateManifest.signedText: notes are last because they
        # are the only field allowed to contain line breaks.
        return '\n'.join((self.version, str(self.build), self.file, str(self.size),
                          self.sha256, self.notes))

    def is_valid(self, public_key: str = PUBLIC_KEY) -> bool:
        try:
            key = base64.b64decode(public_key, validate=True)
            signature = base64.b64decode(self.signature, validate=True)
        except (binascii.Error, ValueError, TypeError):
            return False
        return verify_signature(key, signature, self.signed_text().encode('utf-8'))


# --- Ed25519 verification (RFC 8032) -------------------------------------
# Only verification is needed in the app; keeping it here avoids a compiled
# dependency and makes the check easy to audit. Adapted from the RFC's affine
# formulas, using extended coordinates so no modular inverse runs per point.

_P = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493
_D = (-121665 * pow(121666, _P - 2, _P)) % _P
_I = pow(2, (_P - 1) // 4, _P)
_BX = 15112221349535400772501151409588531511454012693041857206046113283949847762202
_BY = 46316835694926478169428394003475163141307993866256225615783033603165251855960
_BASE = (_BX, _BY, 1, _BX * _BY % _P)


def _decode_point(encoded: bytes):
    if len(encoded) != 32:
        return None
    value = int.from_bytes(encoded, 'little')
    sign = value >> 255
    y = value & ((1 << 255) - 1)
    if y >= _P:
        return None
    y2 = y * y % _P
    x2 = (y2 - 1) * pow(_D * y2 + 1, _P - 2, _P) % _P
    if x2 == 0:
        if sign:
            return None
        x = 0
    else:
        x = pow(x2, (_P + 3) // 8, _P)
        if (x * x - x2) % _P:
            x = x * _I % _P
        if (x * x - x2) % _P:
            return None
        if (x & 1) != sign:
            x = _P - x
    return (x, y, 1, x * y % _P)


def _point_add(first, second):
    x1, y1, z1, t1 = first
    x2, y2, z2, t2 = second
    a = (y1 - x1) * (y2 - x2) % _P
    b = (y1 + x1) * (y2 + x2) % _P
    c = 2 * _D * t1 * t2 % _P
    d = 2 * z1 * z2 % _P
    e = (b - a) % _P
    f = (d - c) % _P
    g = (d + c) % _P
    h = (b + a) % _P
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _point_double(point):
    x, y, z, _ = point
    a = x * x % _P
    b = y * y % _P
    c = 2 * z * z % _P
    d = -a % _P
    e = ((x + y) ** 2 - a - b) % _P
    g = (d + b) % _P
    f = (g - c) % _P
    h = (d - b) % _P
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _scalar_mult(scalar: int, point):
    result = (0, 1, 1, 0)
    addend = point
    while scalar:
        if scalar & 1:
            result = _point_add(result, addend)
        addend = _point_double(addend)
        scalar >>= 1
    return result


def _points_equal(first, second) -> bool:
    x1, y1, z1, _ = first
    x2, y2, z2, _ = second
    return (x1 * z2 - x2 * z1) % _P == 0 and (y1 * z2 - y2 * z1) % _P == 0


def verify_signature(public_key: bytes, signature: bytes, message: bytes) -> bool:
    """Check an Ed25519 signature the way CryptoKit produced it."""
    if len(public_key) != 32 or len(signature) != 64:
        return False
    left = _decode_point(public_key)
    right = _decode_point(signature[:32])
    if left is None or right is None:
        return False
    scalar = int.from_bytes(signature[32:], 'little')
    if scalar >= _L:
        return False
    challenge = int.from_bytes(
        hashlib.sha512(signature[:32] + public_key + message).digest(), 'little'
    ) % _L
    return _points_equal(
        _scalar_mult(scalar, _BASE),
        _point_add(right, _scalar_mult(challenge, left)),
    )


# --- Manifest and package -------------------------------------------------

def _safe_member(name: str) -> bool:
    """A relative bucket or ZIP path with no traversal or drive letter."""
    if not name or name.startswith(('/', '\\')) or '\\' in name or ':' in name:
        return False
    parts = name.split('/')
    return all(part not in ('', '.', '..') for part in parts)


def base_url(base: str | None = None) -> str:
    return (base or os.environ.get('PRISMA_WINDOWS_UPDATES_URL') or DEFAULT_BASE).rstrip('/')


def manifest_url(base: str | None = None) -> str:
    return f'{base_url(base)}/{MANIFEST_NAME}'


def package_url(manifest: Manifest, base: str | None = None) -> str:
    return f'{base_url(base)}/{quote(manifest.file, safe="/")}'


def _open(request, timeout=TIMEOUT):
    return urllib.request.urlopen(request, timeout=timeout)


def _request(url: str):
    return urllib.request.Request(url, headers={
        'User-Agent': 'Prisma-Windows',
        # A cached manifest would hide a new version for hours.
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
    })


def fetch_manifest(base: str | None = None, opener=_open) -> Manifest:
    try:
        with opener(_request(manifest_url(base)), timeout=TIMEOUT) as response:
            status = getattr(response, 'status', 200)
            if status != 200:
                raise UpdateError('El servidor de actualizaciones no respondió.')
            raw = response.read(MAX_MANIFEST + 1)
    except UpdateError:
        raise
    except Exception as error:
        raise UpdateError(f'No se pudo consultar la actualización: {error}') from error
    if len(raw) > MAX_MANIFEST:
        raise UpdateError('El manifiesto de actualizaciones es demasiado grande.')
    return Manifest.from_json(raw)


def check(current_build: int, base: str | None = None, opener=_open) -> Manifest | None:
    """Return the published manifest only when it is newer than this build."""
    manifest = fetch_manifest(base, opener)
    if not manifest.is_valid():
        raise UpdateError('La versión publicada no tiene una firma válida.')
    return manifest if manifest.build > current_build else None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        while True:
            block = handle.read(1 << 20)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def download(manifest: Manifest, destination: Path, base: str | None = None,
             opener=_open, progress=None) -> Path:
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    received = 0
    try:
        with opener(_request(package_url(manifest, base)), timeout=TIMEOUT) as response:
            status = getattr(response, 'status', 200)
            if status != 200:
                raise UpdateError('El servidor no entregó la versión nueva.')
            with open(destination, 'wb') as handle:
                while True:
                    block = response.read(1 << 16)
                    if not block:
                        break
                    received += len(block)
                    if received > manifest.size:
                        raise UpdateError('El archivo descargado no coincide con la versión publicada.')
                    handle.write(block)
                    if progress:
                        progress(min(1.0, received / manifest.size))
    except UpdateError:
        destination.unlink(missing_ok=True)
        raise
    except Exception as error:
        destination.unlink(missing_ok=True)
        raise UpdateError(f'No se pudo descargar la actualización: {error}') from error
    if received != manifest.size:
        destination.unlink(missing_ok=True)
        raise UpdateError('El archivo descargado no coincide con la versión publicada.')
    return destination


def verify_package(package: Path, manifest: Manifest) -> None:
    package = Path(package)
    try:
        size = package.stat().st_size
    except OSError as error:
        raise UpdateError('No se encontró el archivo descargado.') from error
    if size != manifest.size or sha256_file(package) != manifest.sha256:
        raise UpdateError('El archivo descargado no coincide con la versión publicada.')


def extract(package: Path, destination: Path) -> Path:
    """Unpack a verified ZIP without allowing paths outside the workspace."""
    destination = Path(destination)
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    try:
        with zipfile.ZipFile(package) as archive:
            broken = archive.testzip()
            if broken:
                raise UpdateError('El paquete de actualización está dañado.')
            total = 0
            for info in archive.infolist():
                name = info.filename.rstrip('/')
                if not _safe_member(name):
                    raise UpdateError('El paquete de actualización contiene una ruta no permitida.')
                mode = (info.external_attr >> 16) & 0o170000
                if mode == 0o120000:
                    raise UpdateError('El paquete de actualización contiene un enlace no permitido.')
                if info.flag_bits & 0x1:
                    raise UpdateError('El paquete de actualización está cifrado.')
                total += info.file_size
                if total > MAX_UNPACKED:
                    raise UpdateError('El paquete de actualización es demasiado grande.')
                target = destination / name
                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as source, open(target, 'wb') as sink:
                    shutil.copyfileobj(source, sink, 1 << 16)
    except UpdateError:
        raise
    except (OSError, zipfile.BadZipFile) as error:
        raise UpdateError('No se pudo descomprimir la actualización.') from error
    root = destination / 'Prisma'
    if not (root / 'windows' / 'app.py').is_file():
        raise UpdateError('El paquete descargado no tiene el formato de Prisma.')
    return root


def staged_version(staged: Path) -> tuple[str, int]:
    common = Path(staged) / 'windows' / 'common.py'
    try:
        text = common.read_text(encoding='utf-8')
    except OSError as error:
        raise UpdateError('El paquete descargado no incluye la versión de Prisma.') from error
    version = re.search(r"^VERSION = '([^']+)'", text, re.M)
    build = re.search(r'^BUILD = (\d+)\s*$', text, re.M)
    if not version or not build:
        raise UpdateError('El paquete descargado no incluye la versión de Prisma.')
    return version.group(1), int(build.group(1))


def prepare(package: Path, manifest: Manifest, workspace: Path) -> Path:
    """Verify and unpack a download, and require the announced version."""
    verify_package(package, manifest)
    staged = extract(package, Path(workspace) / 'nuevo')
    version, build = staged_version(staged)
    if version != manifest.version or build != manifest.build:
        raise UpdateError('El paquete descargado no es la versión anunciada.')
    return staged


# --- Replacing the installed runtime -------------------------------------

def _replace_file(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.prisma-new')
    shutil.copy2(source, temporary)
    for attempt in range(10):
        try:
            os.replace(temporary, target)
            return
        except OSError:
            if attempt == 9:
                raise
            time.sleep(.2)


def _replace_tree(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.prisma-new')
    if temporary.exists():
        shutil.rmtree(temporary)
    shutil.copytree(source, temporary)
    if target.exists():
        shutil.rmtree(target)
    for attempt in range(10):
        try:
            temporary.rename(target)
            return
        except OSError:
            if attempt == 9:
                raise
            time.sleep(.2)


def backup_runtime(support: Path) -> Path:
    support = Path(support)
    backup = support / 'update-backup'
    if backup.exists():
        shutil.rmtree(backup)
    backup.mkdir(parents=True)
    for path in sorted(support.glob('*.py')):
        shutil.copy2(path, backup / path.name)
    requirements = support / 'requirements.txt'
    if requirements.is_file():
        shutil.copy2(requirements, backup / requirements.name)
    plugin = support / 'plugin-dist' / 'plugin'
    if plugin.is_dir():
        shutil.copytree(plugin, backup / 'plugin')
    return backup


def install_files(staged: Path, support: Path) -> list[str]:
    """Copy the staged runtime over the installed one, keeping user data."""
    staged = Path(staged)
    support = Path(support)
    windows = staged / 'windows'
    if not (windows / 'app.py').is_file():
        raise UpdateError('El paquete descargado no tiene el formato de Prisma.')
    backup_runtime(support)
    changed = []
    for source in sorted(windows.glob('*.py')):
        _replace_file(source, support / source.name)
        changed.append(source.name)
    requirements = windows / 'requirements.txt'
    if requirements.is_file():
        _replace_file(requirements, support / 'requirements.txt')
        changed.append('requirements.txt')
    plugin = staged / 'plugin'
    if (plugin / 'AGENTS.md').is_file():
        _replace_tree(plugin, support / 'plugin-dist' / 'plugin')
        changed.append('plugin')
    return changed


def requirements_changed(staged: Path, support: Path) -> bool:
    source = Path(staged) / 'windows' / 'requirements.txt'
    target = Path(support) / 'requirements.txt'
    if not source.is_file():
        return False
    try:
        return source.read_bytes() != target.read_bytes()
    except OSError:
        return True


def install_requirements(staged: Path, support: Path, log_path: Path | None = None) -> bool:
    source = Path(staged) / 'windows' / 'requirements.txt'
    if not source.is_file():
        return True
    support = Path(support)
    target = support / 'requirements.txt'
    if not requirements_changed(staged, support):
        if not target.is_file():
            _replace_file(source, target)
        return True
    python = support / 'venv' / 'Scripts' / 'python.exe'
    if not python.is_file():
        python = Path(sys.executable)
    command = [str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '-r', str(source)]
    output = open(log_path, 'a', encoding='utf-8') if log_path else nullcontext(subprocess.DEVNULL)
    try:
        with output as handle:
            result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT,
                                    timeout=900, creationflags=NO_WINDOW)
    except (OSError, subprocess.SubprocessError):
        return False
    if result.returncode != 0:
        return False
    _replace_file(source, target)
    return True


def finish_update(support: Path) -> None:
    backup = Path(support) / 'update-backup'
    if backup.exists():
        shutil.rmtree(backup, ignore_errors=True)


def rollback(support: Path) -> bool:
    support = Path(support)
    backup = support / 'update-backup'
    if not backup.is_dir():
        return False
    for source in sorted(backup.glob('*.py')):
        _replace_file(source, support / source.name)
    requirements = backup / 'requirements.txt'
    if requirements.is_file():
        _replace_file(requirements, support / 'requirements.txt')
    plugin = backup / 'plugin'
    if plugin.is_dir():
        _replace_tree(plugin, support / 'plugin-dist' / 'plugin')
    shutil.rmtree(backup, ignore_errors=True)
    return True


def wait_for_exit(pid: int, timeout: float = 60) -> bool:
    """Wait until the tray app has closed, so its modules can be replaced."""
    if os.name != 'nt':
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            except PermissionError:
                pass
            time.sleep(.2)
        return False
    import ctypes
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(0x00100000, False, int(pid))  # SYNCHRONIZE
    if not handle:
        return True
    try:
        return kernel32.WaitForSingleObject(handle, int(timeout * 1000)) == 0
    finally:
        kernel32.CloseHandle(handle)


def _pythonw(support: Path) -> Path:
    executable = Path(support) / 'venv' / 'Scripts' / 'pythonw.exe'
    return executable if executable.is_file() else Path(sys.executable)


def launch_helper(staged: Path, support: Path, pid: int, workspace: Path | None = None) -> subprocess.Popen:
    staged = Path(staged)
    support = Path(support)
    workspace = Path(workspace) if workspace is not None else staged.parent
    helper = staged / 'windows' / 'update_helper.py'
    if not helper.is_file():
        raise UpdateError('El paquete no incluye el instalador de la actualización.')
    flags = getattr(subprocess, 'DETACHED_PROCESS', 0) | getattr(subprocess, 'CREATE_NEW_PROCESS_GROUP', 0)
    return subprocess.Popen(
        [str(_pythonw(support)), str(helper), str(pid), str(staged), str(support),
         str(support / 'prisma.log'), str(workspace)],
        cwd=str(workspace), creationflags=flags, close_fds=True,
    )


def restart(support: Path, attempts: int = 3) -> bool:
    support = Path(support)
    app = support / 'app.py'
    flags = getattr(subprocess, 'DETACHED_PROCESS', 0) | getattr(subprocess, 'CREATE_NEW_PROCESS_GROUP', 0)
    for _ in range(attempts):
        try:
            process = subprocess.Popen(
                [str(_pythonw(support)), str(app)], cwd=str(support),
                creationflags=flags, close_fds=True,
            )
        except OSError:
            time.sleep(1)
            continue
        time.sleep(2)
        if process.poll() is None:
            return True
        time.sleep(1)
    return False

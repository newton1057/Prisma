"""Replace Prisma's runtime after the tray app exits and open it again.

The updater launches this file with pythonw and passes the app's PID, the
verified staging folder, the support folder and the log. Windows cannot
replace modules that a running process has open, so the update is applied
only after the app has closed. If installing new requirements fails, the
previous runtime is restored and Prisma is opened again.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import updater


def note(path: Path, text: str) -> None:
    line = f'{datetime.now():%Y-%m-%d %H:%M:%S} actualizacion: {text}\n'
    try:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write(line)
    except OSError:
        pass


def main() -> int:
    pid, staged, support, log = (int(sys.argv[1]), Path(sys.argv[2]),
                                 Path(sys.argv[3]), Path(sys.argv[4]))
    workspace = Path(sys.argv[5]) if len(sys.argv) > 5 else staged.parent
    note(log, 'esperando a que cierre la app')
    if not updater.wait_for_exit(pid, 60):
        note(log, 'la app no se cerró; se cancela la actualización')
        return 1
    try:
        changed = updater.install_files(staged, support)
        note(log, 'archivos reemplazados: ' + ', '.join(changed))
        if not updater.install_requirements(staged, support, log):
            updater.rollback(support)
            note(log, 'no se pudieron instalar las dependencias; se restauró la versión anterior')
            updater.restart(support)
            return 1
        updater.finish_update(support)
        if updater.restart(support):
            note(log, 'reabierta')
            shutil.rmtree(workspace, ignore_errors=True)
            return 0
        note(log, 'no se pudo reabrir; abre Prisma desde el menú Inicio')
        return 1
    except Exception as error:
        try:
            updater.rollback(support)
        except Exception:
            pass
        note(log, f'error: {error}; se restauró la versión anterior')
        try:
            updater.restart(support)
        except Exception:
            pass
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

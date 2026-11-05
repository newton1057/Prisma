#!/usr/bin/env python3
"""Impide publicar en el bucket público un paquete con credenciales o configuración local."""

import os
import re
import sys
import zipfile
from pathlib import Path

PATRONES = [
    re.compile(rb"AIza[0-9A-Za-z_-]{30,}"),
    re.compile(rb"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(rb"ghp_[A-Za-z0-9]{20,}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]
NOMBRES_PROHIBIDOS = ("config.json", "runtime.json", "credencial", ".env", "id_rsa")


def secreto_de_prueba() -> bytes:
    """Una cadena que nunca aparece; vacía haría que todo coincidiera."""
    return os.environ.get("PRISMA_SECRETO_VERIFICACION", "\0prisma-no-tiene-secreto\0").encode()


def problemas(paquete: Path) -> list[str]:
    exacta = secreto_de_prueba()
    hallados = []
    with zipfile.ZipFile(paquete) as archivo:
        for entrada in archivo.infolist():
            if any(nombre in entrada.filename for nombre in NOMBRES_PROHIBIDOS):
                hallados.append(f"{entrada.filename}: archivo de credenciales")
            elif not entrada.is_dir():
                contenido = archivo.read(entrada)
                if exacta in contenido or any(patron.search(contenido) for patron in PATRONES):
                    hallados.append(f"{entrada.filename}: contiene una clave")
    return hallados


def main() -> int:
    if len(sys.argv) != 2:
        print("Uso: verificar_paquete.py <paquete.zip>", file=sys.stderr)
        return 2
    hallados = problemas(Path(sys.argv[1]))
    for problema in hallados:
        print(f"NO PUBLICAR · {problema}", file=sys.stderr)
    if not hallados:
        print("Paquete sin credenciales.")
    return 1 if hallados else 0


if __name__ == "__main__":
    sys.exit(main())

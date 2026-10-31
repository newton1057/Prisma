# Comparativa de voces locales

Objetivo: voz en español, 100 % local, ligera y con buena latencia en un Mac
Apple Silicon (16 GB RAM).

## Verificadas en este equipo

| Motor | Voz | Tamaño | Licencia | Calidad | Latencia | Muestra |
|---|---|---|---|---|---|---|
| Apple `say` | Paulina (es-MX) | 0 MB | Apple | Media, algo robótica | Instantánea | `samples/apple_paulina.m4a` |
| Apple `say` | Mónica (es-ES) | 0 MB | Apple | Media, algo robótica | Instantánea | `samples/apple_monica.m4a` |
| **Piper** | **es_MX-claude-high** | **60 MB + runtime** | **GPL-3.0 (runtime nuevo)** | **Buena, natural** | **~1,2 s/frase** | **`samples/piper_claude.m4a`** |

Piper se probó con el modelo `es_MX-claude-high.onnx` (22 050 Hz). Sintetizó
4,78 s de audio en 1,18 s, incluyendo el arranque del proceso.

## Otras opciones verificadas por documentación

| Motor | Voz | Tamaño | Licencia | Calidad | Notas |
|---|---|---|---|---|---|
| Kokoro-82M | `ef_dora`, `em_alex`, `em_santa` | 92 MB (q8) + ~100 MB runtime | Apache-2.0 | Muy buena | Requiere G2P español (espeak/misaki). |
| Supertonic 3 | 99M, 31 idiomas, voces M1–F5 | ~400 MB | OpenRAIL-M | Muy buena | Muy rápida en CPU; la más pesada. |
| Piper | es_ES-sharvard-medium | 77 MB | GPL-3.0 | Buena | Acento de España. |
| Piper | es_AR-daniela-high | 114 MB | GPL-3.0 | Buena | Acento argentino. |
| Piper | es_MX-ald-medium | 63 MB | GPL-3.0 | Buena | Voz masculina. |
| Piper | es_ES-carlfm-x_low | 28 MB | GPL-3.0 | Básica | La más ligera; calidad inferior. |

## Decisión

**Piper `es_MX-claude-high`** es la voz principal:

- 60 MB de modelo, muy por debajo de Kokoro/Supertonic.
- Voz femenina en español de México, clara y natural.
- Funciona sin GPU y sin conexión.
- Apple Paulina queda como fallback instantáneo.

**Kokoro-82M** sería el siguiente salto de calidad si Piper no convence; el
modelo cuantizado q8 pesa 92 MB y el runtime añade ~100 MB.

**Supertonic 3** queda descartado para “no tan pesado”: ~400 MB solo de modelo.

## Runtime instalado

El entorno de Piper y Edge Neural se copió a:

```
~/Library/Application Support/Prisma/venv/
~/Library/Application Support/Prisma/voices/es_MX-claude-high.onnx
```

El proyecto ya no necesita mantener `.venv` en `~/Desktop/Prisma`. Si hace
falta recrearlo:

```bash
./setup_voice.sh
```

## Cómo escuchar

```bash
open ~/Desktop/Prisma/samples/comparacion_voces.m4a
open ~/Desktop/Prisma/samples/piper_claude_resumen.m4a
```

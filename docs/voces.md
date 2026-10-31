# Local voice comparison

Goal: a lightweight, fully local Spanish voice with good latency on an Apple Silicon Mac with 16 GB of RAM. These are historical evaluation notes; Edge Ava Multilingual is now the default voice.

## Tested on this machine

| Engine | Voice | Size | License | Quality | Latency | Sample |
|---|---|---|---|---|---|---|
| Apple `say` | Paulina (es-MX) | 0 MB | Apple | Moderate, somewhat robotic | Instant | `samples/apple_paulina.m4a` |
| Apple `say` | Mónica (es-ES) | 0 MB | Apple | Moderate, somewhat robotic | Instant | `samples/apple_monica.m4a` |
| **Piper** | **es_MX-claude-high** | **60 MB + runtime** | **GPL-3.0 (new runtime)** | **Good, natural** | **~1.2 s/sentence** | **`samples/piper_claude.m4a`** |

Piper was tested with `es_MX-claude-high.onnx` at 22,050 Hz. It synthesized 4.78 seconds of audio in 1.18 seconds, including process startup.

## Other options reviewed in documentation

| Engine | Voice | Size | License | Quality | Notes |
|---|---|---|---|---|---|
| Kokoro-82M | `ef_dora`, `em_alex`, `em_santa` | 92 MB (q8) + ~100 MB runtime | Apache-2.0 | Very good | Requires Spanish G2P (espeak/misaki). |
| Supertonic 3 | 99M, 31 languages, M1–F5 voices | ~400 MB | OpenRAIL-M | Very good | Very fast on CPU; largest option. |
| Piper | es_ES-sharvard-medium | 77 MB | GPL-3.0 | Good | Spanish accent from Spain. |
| Piper | es_AR-daniela-high | 114 MB | GPL-3.0 | Good | Argentinian accent. |
| Piper | es_MX-ald-medium | 63 MB | GPL-3.0 | Good | Male voice. |
| Piper | es_ES-carlfm-x_low | 28 MB | GPL-3.0 | Basic | Lightest option; lower quality. |

## Original decision

**Piper `es_MX-claude-high`** was selected as the primary local voice because its 60 MB model is smaller than Kokoro and Supertonic, it provides a clear, natural female Mexican Spanish voice, and it works without a GPU or internet. Apple Paulina remains an immediate fallback. Edge Ava Multilingual has since become the app's default.

Kokoro-82M was identified as a possible quality upgrade, with a 92 MB q8 model and approximately 100 MB runtime. Supertonic 3 was considered too large for the lightweight goal at roughly 400 MB for the model alone.

## Installed runtime

The Piper and Edge Neural environment was copied to:

```text
~/Library/Application Support/Prisma/venv/
~/Library/Application Support/Prisma/voices/es_MX-claude-high.onnx
```

The project does not need to keep `.venv` in `~/Desktop/Prisma`. If it needs to be recreated, run `./setup_voice.sh`.

## Listen to the samples

```bash
open ~/Desktop/Prisma/samples/comparacion_voces.m4a
open ~/Desktop/Prisma/samples/piper_claude_resumen.m4a
```

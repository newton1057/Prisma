# Atenuación del audio de fondo (ducking)

Fecha: 2026-10-30
Estado: implementado y verificado en macOS 26.4 (Apple Silicon)
Commit: `f1366c9` — *Atenúa el audio del sistema mientras Prisma habla*

## 1. Qué hace

Cuando Prisma empieza a hablar:

1. Baja suavemente el volumen del dispositivo de salida del Mac (35% por
   defecto) para que la música, un video o una llamada queden de fondo.
2. Compensa su propia voz con ganancia y un limitador de picos, para que se
   entienda claramente por encima del audio atenuado.
3. Al terminar, restaura el volumen anterior con una rampa corta.

Se puede desactivar o ajustar en **Ajustes → Audio de fondo**:

- *Bajar música y videos mientras Prisma habla* (activado por defecto).
- *Volumen mientras hablo*: 15%–70%, en pasos de 5% (35% por defecto).

## 2. Por qué se implementó así

macOS no ofrece una API pública para atenuar **una sola aplicación**. Las
alternativas viables eran:

| Opción | Resultado |
|---|---|
| Bajar el volumen del dispositivo de salida (CoreAudio) | Simple, funciona con cualquier app y reproductor. Afecta a todo el sistema. **Elegida.** |
| Capturar y remezclar el audio de otras apps (CoreAudio taps, macOS 14.4+) | Requiere permisos de captura de audio y un grafo por proceso. Se deja como mejora futura. |
| Silenciar apps concretas con APIs privadas | Frágil y no distribuible. Descartada. |

Como el volumen global también baja la voz de Prisma, la voz se compensa:

```text
compensación (dB) = 20 · log10(volumen_base / volumen_atenuado)
```

con un tope de **+12 dB** para no forzar el motor ni el limitador. La ganancia
se aplica antes de un `PeakLimiter` de Apple, de modo que la voz sube sin
distorsionar.

También se sustituyó `AVAudioPlayer` por `AVAudioEngine` +
`AVAudioUnitEffect` (PeakLimiter) en `SpeechSession`. `AVAudioPlayer` no permite
aplicar ganancia positiva ni limitar picos, así que no servía para compensar.

## 3. Flujo completo

```text
POST /speak
   │
   ├─ Se sintetiza el primer fragmento (Edge / Piper)
   │
   ├─ SpeechSession, justo antes del primer play:
   │     duckBoost()  ──►  SpeechController.startDuckingForVoice()
   │                          ├─ ¿duckAudio activo?  no → restaura y devuelve 0
   │                          └─ SystemAudioDucker.duck(to: duckLevel)
   │                                ├─ lee volumen actual del dispositivo por defecto
   │                                ├─ calcula objetivo y compensación
   │                                ├─ rampa de bajada (0.35 s)
   │                                └─ programa watchdog de 10 min
   │
   ├─ pre-roll de 0.32 s (solo si hay compensación)
   │     └─ da tiempo a que la música baje antes de la primera palabra
   │
   ├─ Reproducción con AVAudioEngine
   │     └─ preGain (+dB) → PeakLimiter → mainMixer → salida
   │
   ├─ Cada fragmento: keepAlive() refresca el watchdog
   │
   └─ Fin, /stop, cierre normal o SIGTERM
         └─ restore() / restoreImmediately()
               └─ rampa de subida (0.5 s) al volumen anterior
```

## 4. Componentes

| Archivo | Responsabilidad |
|---|---|
| `app/Sources/Prisma/SystemAudioDucker.swift` | Lee y escribe el volumen del dispositivo por CoreAudio, calcula la compensación, hace las rampas, respeta cambios manuales del usuario y ejecuta el watchdog. |
| `app/Sources/Prisma/SpeechController.swift` | Decide cuándo atenuar (justo antes del primer play), aplica el pre-roll, pasa la ganancia al limitador y restaura en `finish`, `stop` y `shutdown`. |
| `app/Sources/Prisma/SettingsStore.swift` | Persiste `duckAudio` (Bool, por defecto `true`) y `duckLevel` (Double, por defecto `0.35`). |
| `app/Sources/Prisma/SettingsView.swift` | Sección **Audio de fondo** con interruptor, deslizador y texto explicativo. |
| `app/Sources/Prisma/AppDelegate.swift` | `applicationWillTerminate` y handler de `SIGTERM` llaman a `SpeechController.shutdown()` para restaurar el volumen. |

## 5. Parámetros y valores

| Parámetro | Valor | Dónde |
|---|---|---|
| Nivel de atenuación por defecto | 35% | `SettingsStore` |
| Rango del ajuste | 15%–70%, paso 5% | `SettingsView` |
| Límite interno del factor | 10%–85% | `SystemAudioDucker.duck` |
| Volumen mínimo para atenuar | > 0.02 | `SystemAudioDucker.duck` |
| Compensación máxima | +12 dB | `SystemAudioDucker` y `applyLimiterGain` |
| Rampa de bajada | 0.35 s | `SystemAudioDucker` |
| Rampa de subida | 0.5 s | `SystemAudioDucker` |
| Pre-roll antes de la primera palabra | 0.32 s | `SpeechController` |
| Watchdog de seguridad | 600 s, refrescado por fragmento | `SystemAudioDucker` |
| Ducking con voz Apple (fallback) | `max(0.65, duckLevel)` | `SpeechController.speakWithApple` |

La voz Apple usa un ducking más suave porque `AVSpeechSynthesizer` no se puede
compensar con ganancia; atenuar demasiado dejaría la voz de respaldo casi
inaudible.

## 6. Casos límite contemplados

- **Volumen ya muy bajo o silenciado**: si el volumen actual es ≤ 0.02, no se
  atenúa ni se compensa.
- **Dispositivo sin control de volumen** (algunos HDMI, agregados o virtuales):
  `AudioObjectIsPropertySettable` devuelve falso y el ducking se omite sin
  errores.
- **El usuario cambia el volumen mientras Prisma habla**: al restaurar se
  respeta su ajuste en lugar de imponer el volumen anterior.
- **Doble atenuación** (por ejemplo, dos mensajes seguidos): se conserva el
  volumen base original y no se acumulan factores.
- **`/stop`**: restaura de inmediato con rampa.
- **Cierre normal de la app**: `applicationWillTerminate` restaura.
- **`SIGTERM`** (lo usa `install.sh` con `pkill`): handler dedicado que restaura
  antes de salir.
- **Mensaje largo**: el watchdog se refresca en cada fragmento para no cortar
  el volumen a mitad de una frase.
- **Fallo de reproducción**: `finish()` restaura aunque el audio no haya
  llegado a sonar.

## 7. Cómo probarlo

Preparación: pon música o un video en el Mac y ejecuta:

```bash
~/Desktop/Prisma/test.sh "Esto es una prueba de atenuación de audio mientras Prisma habla."
```

Resultado esperado:

1. La música baja antes de la primera palabra.
2. La voz se escucha clara y por encima del fondo.
3. Al terminar, el volumen vuelve suavemente al nivel anterior.

Pruebas de restauración:

```bash
# Restauración con /stop
curl -sS -X POST "http://127.0.0.1:8788/stop" -H "X-Prisma-Token: $(jq -r .token "$HOME/Library/Application Support/Prisma/runtime.json")"

# Cierre normal
osascript -e 'quit app "Prisma"'

# SIGTERM (lo usa install.sh)
pkill -TERM -f "Prisma.app/Contents/MacOS/Prisma"
```

Para observar el volumen del dispositivo durante la prueba se puede usar
`osascript -e 'output volume of (get volume settings)'` en bucle, o el medidor
CoreAudio que se usó durante el desarrollo.

### Evidencia de la sesión de verificación

| Prueba | Resultado |
|---|---|
| Volumen base 1.0 | 1.0 → 0.35 → 1.0 |
| Volumen base 0.5 | 0.5 → 0.175 → 0.5 |
| `/stop` durante el habla | Volumen restaurado |
| Cierre normal de la app | Volumen restaurado |
| `SIGTERM` | Volumen restaurado |
| Ajuste desactivado | El volumen no cambia |
| Compensación de voz (+9 dB) | RMS −20.2 → −13.2 dBFS; pico limitado a 0.0 dBFS |
| Orbe durante el habla | Visible, sin recortes, con animación alimentada por el tap RMS |

## 8. Limitaciones conocidas

- **Es global**: también baja notificaciones, alarmas y llamadas, no solo la
  música. Es el precio de no usar APIs privadas.
- **Solo el dispositivo de salida por defecto**: si el usuario cambia de salida
  a mitad de una frase, el dispositivo nuevo no queda atenuado y la
  restauración se aplica al dispositivo original.
- **`SIGKILL` o cuelgue del proceso**: no hay oportunidad de restaurar; el
  watchdog de 10 minutos solo corre mientras el proceso vive.
- **La voz Apple no se compensa**: el ducking se limita al 65% como mínimo.
- **No hay tests automatizados** de la lógica de rampas y restauración; la
  verificación es manual (ver sección 7).

## 9. Mejoras futuras

1. **Ducking por aplicación**: evaluar CoreAudio process taps (macOS 14.4+)
   para atenuar solo apps de contenido y dejar intactas notificaciones y
   llamadas. Requiere permisos de captura de audio y un grafo de mezcla.
2. **Restauración tras cambio de dispositivo**: observar
   `kAudioHardwarePropertyDefaultOutputDevice` y trasladar el ducking.
3. **Tests unitarios** para `restoreTarget` (rampa en curso, cambio manual,
   doble ducking) y una prueba de integración con un tono de referencia.
4. **Sensibilidad del medidor del orbe**: exponer un ajuste si el RMS resulta
   demasiado conservador con voces suaves.
5. **Rampas configurables** para usuarios que prefieran transiciones más lentas.

## 10. Historial

- **2026-10-30** — Implementación inicial: `SystemAudioDucker`, integración con
  `AVAudioEngine` y PeakLimiter, pre-roll, ajustes de usuario, watchdog,
  restauración en `/stop`, cierre y `SIGTERM`. Verificado manualmente y
  publicado en `main` (`f1366c9`).

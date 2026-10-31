# Roadmap y notas de producto

Última actualización: 2026-10-30
Estado del repo: `main` sincronizado con `origin/main` (`f1366c9`)

## 1. Dónde estamos

Prisma ya cubre el ciclo completo:

- Orbe Liquid Glass flotante, por encima de apps y video, sin robar foco ni
  bloquear clics.
- Voz neural (Edge Ava Multilingüe) con respaldo Piper y Apple Paulina.
- Resumen hablado al final de cada turno de OpenCode, Codex y Claude Code
  mediante el bloque `<ForPrisma>`.
- Aviso por voz cuando un agente abre una pregunta interactiva.
- Atenuación del audio del sistema mientras habla, con compensación de voz,
  pre-roll, watchdog y restauración segura.
- Ajustes de posición, velocidad, voz, visibilidad y audio de fondo.

Documentación técnica del ducking: [`audio-ducking.md`](audio-ducking.md).

## 2. Siguiente iteración sugerida

### 2.1 Decidir en qué pantalla aparece el orbe (prioridad alta)

**Observado:** `OverlayController.position` usa `NSScreen.main` con respaldo en
`NSScreen.screens.first`. En un equipo con monitor externo, `NSScreen.main`
puede ser la pantalla que tiene el foco, no la del Notch. En la prueba del
2026-10-30 el panel apareció en el monitor externo:

- Integrada: `(0, 0, 1710, 1112)`, con Notch y `visibleFrame.y = 36`.
- Externa: `(-1920, 32, 1920, 1080)`.
- Panel resultante: `x = -1190`, `y = 752` (centro superior del monitor externo).

**Opciones:**

| Política | Ventaja | Inconveniente |
|---|---|---|
| Pantalla con el menú (`NSScreen.screens.first`) | Coincide con el Notch y la expectativa visual | Ignora dónde está trabajando el usuario |
| Pantalla del puntero (`NSEvent.mouseLocation`) | Sigue el contexto inmediato | Puede saltar de pantalla sin avisar |
| Pantalla del agente con foco | Coherente con la conversación | `NSScreen.main` ya mostró ser ambiguo con paneles no activantes |
| Ajuste explícito en **Ajustes → Animación** | Control total del usuario | Una opción más que mantener |

**Criterio de aceptación:** con dos pantallas, el orbe aparece siempre en la
pantalla elegida; al cambiar la selección se reposiciona sin reiniciar; la
opción por defecto debe ser la pantalla con el Notch.

### 2.2 Ducking por aplicación (prioridad media)

Hoy se baja el volumen global y también se atenúan notificaciones y alarmas.
Evaluar CoreAudio process taps (macOS 14.4+) para atenuar solo contenido
(música/video) y dejar intactos avisos del sistema. Antes de implementarlo hay
que validar:

- Permiso de captura de audio y texto de privacidad en `Info.plist`.
- Coste de CPU y latencia con varias apps sonando.
- Comportamiento con AirPlay, Bluetooth y dispositivos agregados.
- Plan de respaldo: si el tap falla, volver al ducking global actual.

### 2.3 Pruebas automatizadas (prioridad media)

La lógica más delicada es `SystemAudioDucker.restoreTarget`: decide entre
volver al volumen base o respetar un cambio manual. Extraerla a una función
pura y cubrir:

- Rampa de bajada todavía en curso.
- Usuario cambió el volumen durante el habla.
- Doble `duck()` sin `restore()` intermedio.
- Volumen en 0 o dispositivo sin control de volumen.
- `restoreImmediately()` con y sin `pendingRestoreTarget`.

Además, una prueba de integración con un tono de referencia que mida el RMS
antes y después de la compensación.

### 2.4 Robustez del audio (prioridad baja)

- Observar cambios de dispositivo de salida y trasladar el ducking.
- Reintentar la restauración si `AudioObjectSetPropertyData` falla.
- Exponer la duración de las rampas si se detectan cortes en Bluetooth.

### 2.5 Producto y experiencia (prioridad baja)

- Ajuste de sensibilidad del medidor del orbe para voces suaves.
- Modo de movimiento reducido para accesibilidad.
- Historial breve de los últimos mensajes hablados.
- Atajo global para silenciar o repetir el último resumen.

## 3. Deuda técnica y riesgos

- **Sin tests automatizados** en la app; toda la verificación es manual.
- **Duplicación de la lógica de voz** entre Edge, Piper y Apple: cualquier
  cambio de velocidad o normalización debe probarse en los tres caminos.
- **`install.sh` usa `pkill`**: depende del handler de `SIGTERM` para restaurar
  el volumen. Si se cambia el script, conservar esa señal (o llamar a
  `shutdown()` por otra vía).
- **El watchdog de 10 minutos** solo protege mientras el proceso vive; un
  `SIGKILL` deja el volumen atenuado.
- **El repo no incluye la voz Piper** (~60 MB); `setup_voice.sh` la descarga.
- **La app escucha en el puerto 8788** si el 8787 está ocupado (ARCHIE). Los
  scripts deben leer `runtime.json`, no fijar el puerto.

## 4. Cómo retomar

```bash
cd ~/Desktop/Prisma
git pull
./install.sh                     # compila, instala app y plugins
~/Desktop/Prisma/test.sh "Hola. Prisma está listo."
```

Comprobaciones rápidas:

- `curl -sS http://127.0.0.1:8788/health` (o el puerto de `runtime.json`).
- Ajustes → Audio de fondo: activar/desactivar y mover el nivel.
- Reproducir música y lanzar `test.sh` con un texto largo.

## 5. Registro de decisiones

| Fecha | Decisión | Motivo |
|---|---|---|
| 2026-10-30 | Ducking global por CoreAudio en lugar de APIs privadas | Única vía pública y estable; se compensa la voz con limitador |
| 2026-10-30 | `AVAudioEngine` + PeakLimiter en vez de `AVAudioPlayer` | Permite ganancia positiva y evita distorsión |
| 2026-10-30 | Pre-roll de 0.32 s | Evita que la primera palabra suene antes de que baje la música |
| 2026-10-30 | Restaurar respetando cambios manuales de volumen | No pelear con el usuario |
| 2026-10-30 | Watchdog de 10 min refrescado por fragmento | Protege ante cierres anómalos sin cortar mensajes largos |
| 2026-10-30 | Voz Apple con ducking mínimo del 65% | `AVSpeechSynthesizer` no se puede compensar |

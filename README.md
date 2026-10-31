<div align="center">

# ◈ Prisma

### Tu agente terminó. Prisma te lo cuenta.

Una app nativa para macOS que convierte las respuestas y preguntas de tus agentes de programación en avisos de voz, acompañados de un orbe animado.

**Codex · Claude Code · OpenCode**

[Instalación](#instalación) · [Cómo funciona](#cómo-funciona) · [Configuración](#configuración) · [Solución de problemas](#solución-de-problemas)

</div>

---

Trabajar con un agente no siempre significa quedarse mirando la terminal. Con Prisma puedes seguir con otra tarea y escuchar cuándo terminó, qué hizo o qué necesita de ti.

Cuando llega un aviso, aparece un orbe flotante que reacciona a la voz. No toma el foco ni bloquea tus clics. También puede atenuar el audio de fondo mientras habla y restaurar el volumen al terminar.

## Qué incluye

- **Avisos al terminar y al hacer preguntas.** Prisma se integra con Codex, Claude Code y OpenCode para anunciar resultados y solicitudes de información o confirmación.
- **Resúmenes pensados para escuchar.** Los agentes reciben instrucciones para añadir un breve bloque de voz a sus respuestas; Prisma lo extrae y limpia el texto antes de leerlo.
- **Voces a tu elección.** Usa Edge Neural TTS, Piper local o la voz de Apple. La voz predeterminada es Ava Multilingüe; si Edge falla, Prisma intenta usar Piper y después Apple.
- **Orbe configurable.** Elige su posición y si permanece visible un momento después de hablar.
- **Audio de fondo ajustable.** Baja temporalmente el volumen del dispositivo de salida para que puedas escuchar el aviso. Puedes cambiar la intensidad o desactivarlo.

## Requisitos

- **macOS 15 o posterior.** El proyecto se compila como una app nativa con Swift.
- **Herramientas de desarrollo de Apple** con Swift disponible, además de Git, Python 3 con soporte para `venv`, `curl` y `jq`. Por ejemplo, instala las herramientas de línea de comandos con `xcode-select --install` y `jq` con `brew install jq` si usas Homebrew.
- Al menos uno de los agentes compatibles instalado: Codex, Claude Code u OpenCode.
- Conexión a internet para instalar las dependencias, descargar el modelo de Piper y usar Edge Neural TTS. Piper y la voz de Apple pueden funcionar sin conexión una vez preparados.

## Instalación

Clona el repositorio y ejecuta los dos scripts desde la carpeta del proyecto:

```bash
git clone https://github.com/newton1057/Prisma.git ~/Desktop/Prisma
cd ~/Desktop/Prisma
./setup_voice.sh
./install.sh
```

`setup_voice.sh` crea un entorno de Python, instala `piper-tts` y `edge-tts`, y descarga el modelo de voz de Piper (aproximadamente 60 MB). El modelo no está incluido en el repositorio.

`install.sh` compila y abre la app, la copia a `~/Applications/Prisma.app` y prepara los archivos de voz y configuración en `~/Library/Application Support/Prisma/`. También configura los hooks e instrucciones globales de Codex y, si los detecta, instala la integración de Claude Code y OpenCode. El instalador puede modificar la configuración existente de esos agentes; revisa [install.sh](install.sh) antes de ejecutarlo si quieres conocer los cambios. Sus comandos de instalación de plugins pueden fallar sin detener el script, así que conviene verificar cada integración.

> Si instalas un agente después de Prisma, vuelve a ejecutar `./install.sh` para configurar su integración. Reinicia el agente para que cargue los cambios.

### Comprueba que funciona

1. Busca el icono de Prisma en la barra de menús de macOS y selecciona **Probar voz**. Deberías ver el orbe y escuchar un mensaje.
2. También puedes probarlo desde la carpeta del repositorio:

   ```bash
   ./test.sh "Hola. Prisma está funcionando en tu Mac."
   ```

3. Inicia o reinicia tu agente, pídele una tarea breve y espera a que termine. Prisma debería anunciar el resultado. Para comprobar las preguntas, pide al agente que te haga una pregunta interactiva.

## Cómo funciona

```text
Codex / Claude Code / OpenCode
          │
          │  respuesta final o pregunta
          ▼
 Integración de Prisma
          │
          │  texto preparado para voz
          ▼
 App de Prisma en macOS ──► voz + orbe animado
```

Las integraciones piden al agente que incluya un bloque como este al final de sus respuestas:

```xml
<ForPrisma>
Terminé los cambios y comprobé que funcionan correctamente.
</ForPrisma>
```

Prisma intenta leer el último bloque válido e ignora las etiquetas mencionadas en ejemplos de código. Si el agente no lo incluye, recurre al texto disponible y elimina elementos como enlaces y formato Markdown; por eso el aviso puede ser más largo. En las preguntas interactivas, también puede construir el aviso con la pregunta y sus opciones.

Los hooks de Codex y Claude Code y el plugin de OpenCode envían los avisos a un servidor de la app que escucha en `127.0.0.1`. Las peticiones para hablar y detenerse requieren un token local. La app usa el primer puerto disponible de su rango y registra el puerto activo en `runtime.json`.

## Configuración

Abre **Prisma → Ajustes…** desde el icono de la barra de menús. Allí puedes elegir:

| Ajuste | Opciones |
| --- | --- |
| **Motor y voz** | Edge Neural TTS, Piper local o Apple; Edge ofrece voces multilingües y regionales. |
| **Lectura** | Mensaje completo, resumen corto o solo un aviso. Estos modos se aplican al texto que recibe la app. |
| **Velocidad** | De 0.8× a 1.2×. |
| **Audio de fondo** | Activar o desactivar la atenuación y ajustar su intensidad. |
| **Animación** | Posición del orbe y tiempo de permanencia al terminar. |

La atenuación está activada por defecto y afecta al **volumen global del dispositivo de salida**, incluidas llamadas y notificaciones. Por defecto lo reduce al 35 % de su nivel previo y lo restaura al terminar. Algunos dispositivos no permiten controlar el volumen desde macOS; en ese caso se omite la atenuación. Hay más detalles y limitaciones en [Audio de fondo](docs/audio-ducking.md).

### Probar otras voces

```bash
# Una voz de Edge Neural
./test.sh "Hola, esta es Dalia." --voice dalia

# Seleccionar un motor local
./test.sh "Hola, estoy usando Piper." --engine piper
./test.sh "Hola, estoy usando la voz de Apple." --engine apple
```

Las voces de Edge disponibles incluyen `ava`, `andrew`, `emma`, `brian`, `dalia`, `jorge`, `salome`, `ximena`, `alvaro` y `elena`. También puedes seleccionarlas en Ajustes.

## Privacidad y conexión

La comunicación entre los plugins y la app ocurre en el Mac. **Edge Neural TTS utiliza un servicio en línea:** el texto preparado para el aviso se envía a ese servicio para generar audio. Si prefieres síntesis local, selecciona **Piper Local** o **Apple Paulina** en Ajustes. El instalador también descarga paquetes y el modelo de voz desde internet.

## Solución de problemas

**No veo ni escucho Prisma.** Abre `~/Applications/Prisma.app` y usa **Probar voz** en su menú. Revisa el volumen de salida y, en Ajustes, que el servidor local aparezca activo.

**La prueba de voz funciona, pero el agente no avisa.** Reinicia el agente y vuelve a ejecutar `./install.sh` si lo instalaste después de Prisma. Comprueba que la integración esté habilitada en ese agente; el instalador continúa aunque fallen algunos comandos de plugins. El registro del hook está en `~/Library/Application Support/Prisma/hook.log`.

**Edge no habla o no tengo conexión.** Prueba Piper o Apple desde Ajustes. Si Piper aparece como no encontrado, ejecuta `./setup_voice.sh` seguido de `./install.sh` y comprueba de nuevo.

**El orbe aparece en otra pantalla.** En configuraciones con varios monitores, actualmente puede aparecer en la pantalla que macOS considera principal; la selección explícita de pantalla está pendiente. Puedes cambiar la posición del orbe en Ajustes.

**El volumen quedó bajo.** Prisma intenta restaurarlo al terminar y al cerrar normalmente. Si el proceso se cierra de forma forzada o falla, ajústalo manualmente desde macOS. Puedes desactivar la atenuación en Ajustes.

## Estructura del proyecto

```text
app/                 App nativa de macOS: interfaz, voz y servidor local
plugin/              Integraciones, hooks y skill para los agentes
docs/                Investigación, decisiones técnicas y roadmap
samples/             Muestras de voces
setup_voice.sh       Prepara las dependencias y el modelo de voz
install.sh           Compila e instala Prisma y sus integraciones
test.sh              Envía un aviso de prueba a la app
```

## Documentación

- [Audio de fondo](docs/audio-ducking.md): funcionamiento, pruebas y limitaciones de la atenuación.
- [Roadmap](docs/roadmap.md): mejoras pendientes y decisiones de producto.
- [Investigación](docs/investigacion.md): mecanismos de integración con los agentes.
- [Comparativa de voces](docs/voces.md): pruebas y muestras de voces locales. Algunas notas reflejan decisiones anteriores; la voz predeterminada actual es Edge Ava Multilingüe.

---

<div align="center">
  Hecho para que puedas seguir trabajando mientras tus agentes trabajan contigo.
</div>

import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const globalState = globalThis as unknown as {
  __prismaSpokenIds?: Set<string>
  __prismaSubagentCache?: Map<string, boolean>
}

if (!globalState.__prismaSpokenIds) {
  globalState.__prismaSpokenIds = new Set<string>()
}
if (!globalState.__prismaSubagentCache) {
  globalState.__prismaSubagentCache = new Map<string, boolean>()
}

const FOR_PRISMA_INSTRUCTION = `## Salida de voz para Prisma

Al final de CADA respuesta —y también SIEMPRE que hagas una pregunta al usuario o solicites confirmación/información para continuar—, añade exactamente este bloque:

<ForPrisma>
Un resumen breve de 1 a 3 frases, en el mismo idioma del usuario, escrito para ser escuchado en voz alta.
</ForPrisma>

Reglas del bloque:
- Es lo único que se pronunciará en voz alta: debe ser autosuficiente, natural y coherente.
- Si estás haciendo una pregunta o usando una herramienta de preguntas (\`question\`), escribe SIEMPRE antes de llamar a la herramienta un breve texto con su bloque \`<ForPrisma>...</ForPrisma>\` formulando claramente la pregunta y mencionando las opciones principales para que el usuario las escuche por voz.
- Resume el resultado, estado o pregunta; no repitas toda la respuesta.
- No incluyas URLs, enlaces, rutas ni nombres de archivos, comandos, código, tablas, viñetas, emojis ni formato Markdown.
- No escribas nada después del bloque de cierre.
- Si no hay nada relevante que decir, escribe una frase corta como "Listo, terminé."`

/**
 * Extrae el contenido del último bloque `<ForPrisma>...</ForPrisma>` (o `<ForPrima>`) real.
 *
 * 1. Elimina antes bloques de código (``` / ~~~) y código en línea (`...`) para no
 *    confundir menciones explicativas de la etiqueta con el bloque final de voz.
 * 2. Usa un prefijo voraz `[\s\S]*` para posicionarse siempre en la última etiqueta
 *    de apertura del mensaje hasta su cierre `</ForPrisma>`.
 */
const LAST_TAG_RE =
  /[\s\S]*<\s*ForPri(?:s)?ma\s*>([\s\S]*?)(?:<\s*\/\s*ForPri(?:s)?ma\s*>|$)/i

function extractTaggedSection(text: string): string {
  const withoutCode = text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/~~~[\s\S]*?~~~/g, " ")
    .replace(/`[^`\n]*`/g, " ")
  const match = withoutCode.match(LAST_TAG_RE)
  return match ? match[1].trim() : ""
}

function extractMarkdownSection(text: string): string {
  const lines = text.split("\n")
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i]
    if (!/^\s*(?:#{1,6}\s*)?(?:\*\*)?For\s*Pri(?:s)?ma\b/i.test(line)) continue

    const inline = line
      .replace(/^\s*(?:#{1,6}\s*)?(?:\*\*)?For\s*Pri(?:s)?ma(?:\*\*)?\s*:?\s*/i, "")
      .trim()
    const rest = lines.slice(i + 1).join("\n").trim()
    return [inline, rest].filter(Boolean).join("\n")
  }
  return ""
}

function cleanForSpeech(input: string): string {
  let text = input.replace(/\r\n/g, "\n").trim()

  // Bloques de código fuera: no se leen.
  text = text.replace(/```[\s\S]*?```/g, " ")
  text = text.replace(/~~~[\s\S]*?~~~/g, " ")

  // Enlaces e imágenes de Markdown: conservar solo la etiqueta.
  text = text.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
  text = text.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")

  // URLs sueltas.
  text = text.replace(/<?https?:\/\/[^\s)>]+>?/gi, " ")
  text = text.replace(/\bwww\.[^\s)>]+/gi, " ")

  // Rutas absolutas comunes en macOS.
  text = text.replace(
    /(?:^|\s)(?:~\/|\/(?:Users|Applications|Library|System|private|tmp|var)\/)[^\s,;)]*/g,
    " ",
  )

  // Markdown residual.
  text = text.replace(/`([^`]*)`/g, "$1")
  text = text.replace(/^\s{0,3}#{1,6}\s+/gm, "")
  text = text.replace(/^\s{0,3}>\s?/gm, "")
  text = text.replace(/^\s*[-*+]\s+/gm, "")
  text = text.replace(/^\s*\d+[.)]\s+/gm, "")
  text = text.replace(/(\*\*|__)(.*?)\1/g, "$2")
  text = text.replace(/(\*|_)(.*?)\1/g, "$2")
  text = text.replace(/~~(.*?)~~/g, "$1")
  text = text.replace(/<\/?\s*ForPri(?:s)?ma\s*>/gi, " ")

  // Espacios.
  text = text.replace(/[ \t]+/g, " ")
  text = text.replace(/\n{3,}/g, "\n\n")
  return text.trim()
}

function toSpeechText(message: string): string {
  const tagged = extractTaggedSection(message)
  if (tagged) return cleanForSpeech(tagged)

  const markdown = extractMarkdownSection(message)
  if (markdown) return cleanForSpeech(markdown)

  // Compatibilidad: si el modelo no incluyó el bloque, se lee el mensaje
  // completo pero sin URLs, rutas ni markdown.
  return cleanForSpeech(message)
}

function formatQuestionsForSpeech(questions: any[]): string {
  if (!Array.isArray(questions) || questions.length === 0) return ""

  const spokenParts: string[] = []
  for (const q of questions) {
    const rawQuestion = typeof q?.question === "string" ? q.question.trim() : ""
    if (!rawQuestion) continue

    const taggedQ = extractTaggedSection(rawQuestion)
    if (taggedQ) {
      spokenParts.push(cleanForSpeech(taggedQ))
      continue
    }

    const cleanQ = cleanForSpeech(rawQuestion)
    const options: string[] = Array.isArray(q?.options)
      ? q.options
          .map((opt: any) =>
            typeof opt?.label === "string"
              ? opt.label.replace(/\s*\(Recommended\)\s*/gi, "").trim()
              : "",
          )
          .filter(Boolean)
      : []

    if (options.length > 0) {
      spokenParts.push(`${cleanQ} Opciones: ${options.join(", ")}.`)
    } else {
      spokenParts.push(cleanQ)
    }
  }

  return spokenParts.join(" ").trim()
}

function rememberSpoken(key: string): boolean {
  if (!key) return false
  if (globalState.__prismaSpokenIds?.has(key)) return true
  globalState.__prismaSpokenIds?.add(key)
  if ((globalState.__prismaSpokenIds?.size ?? 0) > 500) {
    const first = globalState.__prismaSpokenIds?.values().next().value
    if (first) globalState.__prismaSpokenIds?.delete(first)
  }
  return false
}

async function isSubagent(ctx: any, sessionID: string): Promise<boolean> {
  const cached = globalState.__prismaSubagentCache?.get(sessionID)
  if (cached !== undefined) return cached

  try {
    const raw = await ctx.session.get({ sessionID })
    const info = raw?.data ?? raw
    const subagent = Boolean(info?.parentID)
    globalState.__prismaSubagentCache?.set(sessionID, subagent)
    return subagent
  } catch {
    return false
  }
}

function extractMessageText(message: any): string {
  const parts: any[] = Array.isArray(message?.content)
    ? message.content
    : Array.isArray(message?.parts)
      ? message.parts
      : []

  return parts
    .filter((p) => p?.type === "text" && typeof p?.text === "string")
    .map((p) => p.text.trim())
    .filter(Boolean)
    .join("\n\n")
}

function triggerOnStop(payload: {
  session_id: string
  cwd: string
  last_assistant_message: string
}) {
  const scriptPath = join(
    homedir(),
    "Library",
    "Application Support",
    "Prisma",
    "on_stop.sh",
  )

  const child = spawn("bash", [scriptPath], {
    stdio: ["pipe", "ignore", "ignore"],
  })

  child.stdin.write(
    JSON.stringify({
      hook_event_name: "Stop",
      source: "opencode",
      session_id: payload.session_id,
      cwd: payload.cwd,
      last_assistant_message: payload.last_assistant_message,
    }),
  )
  child.stdin.end()
  child.unref()
}

async function handleQuestionAsked(
  ctx: any,
  sessionID: string,
  questions: any[],
  dedupeToken: string,
) {
  if (!sessionID) return
  if (await isSubagent(ctx, sessionID)) return

  const rawSession = await ctx.session.get({ sessionID }).catch(() => undefined)
  const sessionInfo = rawSession?.data ?? rawSession
  if (sessionInfo?.parentID) return

  const rawMessages = await ctx.session
    .context({ sessionID })
    .catch(() => [])
  const messages: any[] = Array.isArray(rawMessages)
    ? rawMessages
    : (rawMessages?.data ?? [])

  let latestAssistant: any = undefined
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i]
    if (m?.type === "assistant") {
      latestAssistant = m
      break
    }
  }

  const assistantText = latestAssistant ? extractMessageText(latestAssistant) : ""
  const taggedFromAssistant = assistantText
    ? extractTaggedSection(assistantText) || extractMarkdownSection(assistantText)
    : ""
  const fallbackFromQuestions = formatQuestionsForSpeech(questions)

  const voiceText = taggedFromAssistant
    ? cleanForSpeech(taggedFromAssistant)
    : fallbackFromQuestions

  if (!voiceText) return

  const questionSignature = `${sessionID}:q:${voiceText}`
  if (rememberSpoken(questionSignature)) return
  if (dedupeToken && rememberSpoken(`${sessionID}:qtoken:${dedupeToken}`)) return
  if (latestAssistant?.id && taggedFromAssistant) {
    rememberSpoken(`${sessionID}:${latestAssistant.id}`)
  }

  triggerOnStop({
    session_id: sessionID,
    cwd:
      sessionInfo?.directory ??
      ctx?.location?.directory ??
      process.cwd(),
    last_assistant_message: voiceText,
  })
}

export default {
  id: "prisma",
  async setup(ctx: any) {
    const controller = new AbortController()

    // Pide al modelo que cierre cada respuesta y cada pregunta con un bloque pensado para voz.
    if (typeof ctx.session?.hook === "function") {
      await ctx.session.hook("context", async (event: any) => {
        try {
          if (event?.kind && event.kind !== "primary") return
          if (await isSubagent(ctx, event.sessionID)) return

          const system: any[] = Array.isArray(event.system) ? event.system : []
          const already = system.some(
            (part) =>
              part?.type === "text" &&
              typeof part?.text === "string" &&
              part.text.includes("<ForPrisma>"),
          )
          if (already) return

          system.push({ type: "text", text: FOR_PRISMA_INSTRUCTION })
        } catch {
          // Si falla la inyección, el turno continúa normalmente.
        }
      })
    }

    // Hook directo cuando el asistente invoca la herramienta `question`
    if (typeof ctx.tool?.hook === "function") {
      await ctx.tool
        .hook("execute.before", async (event: any) => {
          try {
            const toolName = event?.tool ?? event?.name ?? ""
            if (toolName !== "question") return
            const sessionID: string | undefined =
              event?.sessionID ?? event?.context?.sessionID
            const questions: any[] =
              event?.input?.questions ?? event?.args?.questions ?? []
            const token = String(event?.callID ?? event?.id ?? "")
            if (sessionID) {
              await handleQuestionAsked(ctx, sessionID, questions, token)
            }
          } catch {
            // Ignorar errores para no bloquear la herramienta
          }
        })
        .catch(() => undefined)
    }

    void (async () => {
      try {
        const stream = ctx.event.subscribe({
          types: [
            "session.execution.succeeded",
            "session.idle",
            "question.v2.asked",
            "question.asked",
          ],
          signal: controller.signal,
        })

        for await (const event of stream) {
          try {
            const eventType: string | undefined = event?.type
            if (
              eventType === "question.v2.asked" ||
              eventType === "question.asked"
            ) {
              const props = event?.properties ?? event?.data ?? event
              const sessionID: string | undefined = props?.sessionID
              const questions: any[] = props?.questions ?? []
              const qid = String(props?.id ?? event?.id ?? "")
              if (sessionID) {
                await handleQuestionAsked(ctx, sessionID, questions, qid)
              }
              continue
            }

            const sessionID: string | undefined =
              event?.sessionID ??
              event?.properties?.sessionID ??
              event?.data?.sessionID ??
              event?.info?.id

            if (!sessionID) continue

            const rawSession = await ctx.session
              .get({ sessionID })
              .catch(() => undefined)
            const sessionInfo = rawSession?.data ?? rawSession
            if (sessionInfo?.parentID) continue

            const rawMessages = await ctx.session
              .context({ sessionID })
              .catch(() => [])
            const messages: any[] = Array.isArray(rawMessages)
              ? rawMessages
              : (rawMessages?.data ?? [])

            let lastAssistant: any = undefined
            for (let i = messages.length - 1; i >= 0; i--) {
              const m = messages[i]
              if (m?.type === "assistant" && m?.finish !== "tool-calls") {
                lastAssistant = m
                break
              }
            }

            if (!lastAssistant) continue

            const dedupeKey = `${sessionID}:${lastAssistant.id ?? ""}`
            if (globalState.__prismaSpokenIds?.has(dedupeKey)) continue

            const fullText = extractMessageText(lastAssistant)
            if (!fullText) continue

            const voiceText = toSpeechText(fullText)
            if (!voiceText) continue

            rememberSpoken(dedupeKey)

            triggerOnStop({
              session_id: sessionID,
              cwd:
                sessionInfo?.directory ??
                ctx?.location?.directory ??
                process.cwd(),
              last_assistant_message: voiceText,
            })
          } catch {
            // Ignore per-event errors so the subscriber stays alive
          }
        }
      } catch {
        // Stream ended or aborted on cleanup
      }
    })()

    return () => controller.abort()
  },
}

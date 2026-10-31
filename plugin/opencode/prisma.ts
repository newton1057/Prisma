import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const globalState = globalThis as unknown as {
  __prismaSpokenIds?: Set<string>
}

if (!globalState.__prismaSpokenIds) {
  globalState.__prismaSpokenIds = new Set<string>()
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

export default {
  id: "prisma",
  async setup(ctx: any) {
    const controller = new AbortController()

    void (async () => {
      try {
        const stream = ctx.event.subscribe({
          types: ["session.execution.succeeded", "session.idle"],
          signal: controller.signal,
        })

        for await (const event of stream) {
          try {
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

            const parts: any[] = Array.isArray(lastAssistant.content)
              ? lastAssistant.content
              : Array.isArray(lastAssistant.parts)
                ? lastAssistant.parts
                : []

            const text = parts
              .filter((p) => p?.type === "text" && typeof p?.text === "string")
              .map((p) => p.text.trim())
              .filter(Boolean)
              .join("\n\n")

            if (!text) continue

            globalState.__prismaSpokenIds?.add(dedupeKey)
            if ((globalState.__prismaSpokenIds?.size ?? 0) > 500) {
              const first = globalState.__prismaSpokenIds?.values().next().value
              if (first) globalState.__prismaSpokenIds?.delete(first)
            }

            triggerOnStop({
              session_id: sessionID,
              cwd:
                sessionInfo?.directory ??
                ctx?.location?.directory ??
                process.cwd(),
              last_assistant_message: text,
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

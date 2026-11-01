import assert from "node:assert/strict"
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { pathToFileURL } from "node:url"

const home = await mkdtemp(join(tmpdir(), "prisma-opencode-test-"))
process.env.HOME = home
const support = join(home, "Library", "Application Support", "Prisma")
await mkdir(support, { recursive: true })
for (const script of ["on_turn.sh", "on_stop.sh"]) {
  await writeFile(
    join(support, script),
    `#!/bin/bash\n{ printf '{"argument":"%s","input":' "$1"; cat; printf '}\\n'; } >> "$HOME/${script}.log"\n`,
  )
}

const { default: plugin } = await import(pathToFileURL(join(process.cwd(), "plugin/opencode/prisma.ts")))
const hooks = {}
const subscribers = []
let messages = []
const directory = "/Users/me/project"
const ctx = {
  location: { directory },
  session: {
    hook: async (name, handler) => { hooks[name] = handler },
    get: async ({ sessionID }) => ({ id: sessionID, directory, parentID: sessionID === "child" ? "parent" : undefined }),
    context: async () => messages,
  },
  event: {
    // Every subscription receives the events of the types it asked for.
    subscribe: ({ types }) => {
      const subscriber = { types, queue: [], wake: undefined }
      subscribers.push(subscriber)
      return {
        async *[Symbol.asyncIterator]() {
          while (true) {
            if (!subscriber.queue.length) await new Promise((resolve) => { subscriber.wake = resolve })
            const event = subscriber.queue.shift()
            if (!event) return
            yield event
          }
        },
      }
    },
  },
}
const cleanup = await plugin.setup(ctx)
const emit = (type, data) => {
  for (const subscriber of subscribers) {
    if (!subscriber.types.includes(type)) continue
    subscriber.queue.push({ type, data })
    subscriber.wake?.()
  }
}
const readLog = async (script) => {
  try {
    return (await readFile(join(home, `${script}.log`), "utf8")).split("\n").filter(Boolean).map((line) => {
      const { argument, input } = JSON.parse(line)
      return { argument, ...input }
    })
  } catch { return [] }
}
const waitFor = async (condition) => {
  for (let i = 0; i < 100; i++) {
    if (await condition()) return
    await new Promise((resolve) => setTimeout(resolve, 20))
  }
  throw new Error("Timed out waiting for Prisma event")
}

try {
  // Prisma gives each OpenCode window its waiting orb; the plugin does not
  // announce anything until a session exists.
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.equal((await readLog("on_turn.sh")).length, 0)

  // A new main session takes over its window's orb; subagents do not.
  emit("session.created", { info: { id: "main", directory } })
  emit("session.created", { info: { id: "child", parentID: "main", directory } })
  await waitFor(async () => (await readLog("on_turn.sh")).length === 1)
  await new Promise((resolve) => setTimeout(resolve, 50))
  const [started] = await readLog("on_turn.sh")
  assert.deepEqual(started, { argument: "opencode", hook_event_name: "SessionStart", session_id: "main", directory })

  await hooks.prompt({ sessionID: "main" })
  const turns = await readLog("on_turn.sh")
  assert.equal(turns.length, 2)
  assert.deepEqual(turns[1], { argument: "opencode", hook_event_name: "UserPromptSubmit", session_id: "main", directory })
  messages = [{ id: "answer-1", type: "assistant", parts: [{ type: "text", text: "<ForPrisma>Respuesta lista.</ForPrisma>" }] }]
  emit("session.execution.succeeded", { sessionID: "main" })
  await waitFor(async () => (await readLog("on_stop.sh")).length === 1)
  const [spoken] = await readLog("on_stop.sh")
  assert.equal(spoken.last_assistant_message, "Respuesta lista.")
  assert.equal(spoken.source, "opencode")
  assert.equal(spoken.cwd, directory)
  emit("session.idle", { sessionID: "main" })
  await new Promise((resolve) => setTimeout(resolve, 50))
  assert.equal((await readLog("on_turn.sh")).length, 2)

  await hooks.prompt({ sessionID: "main" })
  emit("session.execution.interrupted", { sessionID: "main" })
  await waitFor(async () => (await readLog("on_turn.sh")).length === 4)
  assert.equal((await readLog("on_turn.sh"))[3].hook_event_name, "Interrupt")

  await hooks.prompt({ sessionID: "main" })
  emit("session.execution.failed", { sessionID: "main" })
  await waitFor(async () => (await readLog("on_turn.sh")).length === 6)
  assert.equal((await readLog("on_turn.sh"))[5].hook_event_name, "Interrupt")

  await hooks.prompt({ sessionID: "child" })
  assert.equal((await readLog("on_turn.sh")).length, 6)
  console.log("OpenCode: session start, prompt, speech, duplicate idle, interruption, failure and subagent checks passed")
} finally {
  cleanup()
  for (const subscriber of subscribers) {
    subscriber.queue.push(null)
    subscriber.wake?.()
  }
  await rm(home, { recursive: true, force: true })
}

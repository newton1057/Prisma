import AppKit

// Agents and their CLIs are spawned from the app; a helper that closes its
// input must not kill Prisma with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import Foundation

/// Owned by one background queue. File reads and process-directory lookups
/// never run on the UI thread; misses expire so a new transcript can appear.
// Safety: AppDelegate confines all calls to its serial metadataQueue. Tests
// use a resolver synchronously; a resolver must never be shared across queues.
final class SessionMetadataResolver: @unchecked Sendable {
    struct Request: Equatable, Sendable {
        let id: String
        let source: String
        let pid: Int32?
        let folder: String?
    }
    private struct CachedTitle {
        let path: URL
        let modified: Date?
        let size: UInt64
        let title: String?
    }
    private let home: URL
    private let clock: () -> TimeInterval
    private let folderLookup: (Int32) -> String?
    private var codexTitles: [String: String] = [:]
    private var codexModified: Date?
    private var nextIndexCheck: TimeInterval = -.infinity
    private var projects: [URL] = []
    private var nextProjectsCheck: TimeInterval = -.infinity
    private var titles: [String: CachedTitle] = [:]
    private var missingUntil: [String: TimeInterval] = [:]
    private var folders: [Int32: (value: String?, until: TimeInterval)] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         folderLookup: @escaping (Int32) -> String? = { _ in nil }) {
        self.home = home
        self.clock = clock
        self.folderLookup = folderLookup
    }

    func remove(_ id: String) {
        titles[id] = nil
        missingUntil[id] = nil
    }

    func resolve(_ request: Request) -> String {
        let now = clock()
        let folder = request.folder ?? request.pid.flatMap { pid -> String? in
            if let cached = folders[pid], cached.until > now { return cached.value }
            let value = folderLookup(pid)
            folders[pid] = (value, now + 10)
            // Process IDs disappear during long-running sessions.
            if folders.count > 128 { folders = folders.filter { $0.value.until > now } }
            return value
        }
        let folderName = folder.map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
        switch request.source {
        case "codex":
            refreshCodexIndex(at: now)
            return codexTitles[request.id.lowercased()] ?? folderName ?? String(request.id.prefix(8))
        case "claude-code":
            return claudeTitle(request.id, at: now) ?? folderName
                ?? (request.id.hasPrefix("claude:") ? "Sesión activa" : String(request.id.prefix(8)))
        case "opencode": return folderName ?? "Sesión activa"
        default: return folderName ?? ""
        }
    }

    private func refreshCodexIndex(at now: TimeInterval) {
        guard now >= nextIndexCheck else { return }
        nextIndexCheck = now + 2
        let url = home.appendingPathComponent(".codex/session_index.jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              modified != codexModified,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (obj["id"] as? String)?.lowercased(),
                  let title = (obj["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            result[id] = title
        }
        codexTitles = result
        codexModified = modified
    }

    private func claudeTitle(_ id: String, at now: TimeInterval) -> String? {
        guard !id.hasPrefix("claude:"), (missingUntil[id] ?? -.infinity) <= now else { return nil }
        let fm = FileManager.default
        let file: URL
        if let cached = titles[id], fm.fileExists(atPath: cached.path.path) {
            file = cached.path
        } else {
            if now >= nextProjectsCheck {
                projects = (try? fm.contentsOfDirectory(at: home.appendingPathComponent(".claude/projects"),
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                nextProjectsCheck = now + 30
            }
            guard let found = projects.map({ $0.appendingPathComponent("\(id).jsonl") })
                .first(where: { fm.fileExists(atPath: $0.path) }) else {
                missingUntil[id] = now + 30
                return nil
            }
            file = found
        }
        guard let attrs = try? fm.attributesOfItem(atPath: file.path) else { return nil }
        let modified = attrs[.modificationDate] as? Date
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        if let cached = titles[id], cached.modified == modified, cached.size == size { return cached.title }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 49_152)) ?? Data()
        var text = String(decoding: head, as: UTF8.self)
        if size > 49_152 {
            try? handle.seek(toOffset: max(49_152, size > 49_152 ? size - 49_152 : 0))
            let tail = (try? handle.read(upToCount: 49_152)) ?? Data()
            text += "\n" + String(decoding: tail, as: UTF8.self)
        }
        var prompt: String?
        var summary: String?
        var custom: String?
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let value = Self.nonempty(obj["customTitle"]) { custom = value }
            if let value = Self.nonempty(obj["summary"]) { summary = value }
            if prompt == nil, obj["type"] as? String == "user",
               let message = obj["message"] as? [String: Any] {
                let content = message["content"]
                let raw = (content as? String) ?? (content as? [[String: Any]])?
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }.joined(separator: " ") ?? ""
                prompt = Self.nonempty(Self.cleanPromptTitle(raw))
            }
        }
        let title = custom ?? summary ?? prompt
        titles[id] = CachedTitle(path: file, modified: modified, size: size, title: title)
        if title == nil { missingUntil[id] = now + 30 } else { missingUntil[id] = nil }
        return title
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func cleanPromptTitle(_ raw: String) -> String {
        if raw.contains("<local-command-") || raw.contains("<command-name>") { return "" }
        let stripped = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let line = stripped.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.count <= 42 ? line : String(line.prefix(40)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

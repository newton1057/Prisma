import Foundation

@main
struct TestSessionMetadata {
    static func main() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("prisma-metadata-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let project = home.appendingPathComponent(".claude/projects/project")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        var now = 100.0
        var folderLookups = 0
        let resolver = SessionMetadataResolver(home: home, clock: { now }, folderLookup: { _ in
            folderLookups += 1
            return "/work/Project"
        })
        let codex = SessionMetadataResolver.Request(id: "ABC", source: "codex", pid: 42, folder: nil)
        let index = home.appendingPathComponent(".codex/session_index.jsonl")
        try #"{"id":"abc","thread_name":"A title"}"#.write(to: index, atomically: true, encoding: .utf8)
        precondition(resolver.resolve(codex) == "A title")
        precondition(resolver.resolve(codex) == "A title" && folderLookups == 1)
        now += 11
        _ = resolver.resolve(codex)
        precondition(folderLookups == 2, "folder cache must expire")

        let request = SessionMetadataResolver.Request(id: "session", source: "claude-code", pid: nil, folder: "/work/Fallback")
        precondition(resolver.resolve(request) == "Fallback")
        let transcript = project.appendingPathComponent("session.jsonl")
        try #"{"type":"user","message":{"content":[{"type":"text","text":"Array prompt"}]}}"#
            .write(to: transcript, atomically: true, encoding: .utf8)
        precondition(resolver.resolve(request) == "Fallback", "misses should be cached")
        now += 31
        precondition(resolver.resolve(request) == "Array prompt", "new transcripts must appear after the miss expires")
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + String(repeating: " ", count: 120_000)
            + "\n" + #"{"customTitle":"Renamed session"}"# + "\n").utf8))
        try handle.close()
        precondition(resolver.resolve(request) == "Renamed session", "a custom title appended at the tail must replace the prompt")

        let watchFile = home.appendingPathComponent("watch.jsonl")
        try #"{"text":"Quoted \"text\":\"[Request interrupted by user"}"#
            .write(to: watchFile, atomically: true, encoding: .utf8)
        let watch = TranscriptWatch(path: watchFile.path, offset: 0, generation: 1)
        let first = ThinkingTranscriptReader.read(watch)!
        precondition(!first.interrupted, "escaped quotes in replies must not count as interruptions")
        let append = try FileHandle(forWritingTo: watchFile)
        try append.seekToEnd()
        try append.write(contentsOf: Data(("\n" + #"{"text":"[Request interrupted by user]"}"#).utf8))
        try append.close()
        let second = ThinkingTranscriptReader.read(TranscriptWatch(path: watchFile.path, offset: first.offset, generation: 1))!
        precondition(second.interrupted)
        precondition(ThinkingTranscriptReader.read(TranscriptWatch(path: watchFile.path, offset: second.offset, generation: 1)) == nil)
        print("Session metadata cache and background transcript reads passed")
    }
}

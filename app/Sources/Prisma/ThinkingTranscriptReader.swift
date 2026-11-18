import Foundation

struct TranscriptWatch: Equatable, Sendable {
    let path: String
    var offset: UInt64
    let generation: UInt64
}

enum ThinkingTranscriptReader {
    struct Result {
        let offset: UInt64
        let interrupted: Bool
    }

    /// Bound the read to the captured end even if the agent keeps appending.
    static func read(_ watch: TranscriptWatch) -> Result? {
        guard let handle = FileHandle(forReadingAtPath: watch.path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > watch.offset else { return nil }
        let start = max(watch.offset, end > 65_536 ? end - 65_536 : 0)
        do {
            try handle.seek(toOffset: start)
            let data = try handle.read(upToCount: Int(end - start)) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            return Result(offset: start + UInt64(data.count),
                          interrupted: text.contains(#""text":"[Request interrupted by user"#))
        } catch { return nil }
    }
}

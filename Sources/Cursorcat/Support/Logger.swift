import Foundation
import OSLog

enum Log {
    static let subsystem = "com.sunstory.cursorcat"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let poll = Logger(subsystem: subsystem, category: "poll")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let app = Logger(subsystem: subsystem, category: "app")
}

/// Rolling log file at ~/Library/Logs/CursorCat/cursorcat.log.
/// Keeps 3 days of logs, best effort. Never throws to caller.
final class FileLog: @unchecked Sendable {
    static let shared = FileLog()

    private let queue = DispatchQueue(label: "cursorcat.filelog")
    private let fileURL: URL?
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let fm = FileManager.default
        guard let logsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/CursorCat", isDirectory: true)
        else {
            fileURL = nil
            return
        }
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        fileURL = logsDir.appendingPathComponent("cursorcat.log")
        rotateIfNeeded(dir: logsDir)
    }

    func write(_ message: String, category: String = "app") {
        guard let url = fileURL else { return }
        let stamp = formatter.string(from: Date())
        let line = "\(stamp) [\(category)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }

    private func rotateIfNeeded(dir: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        for e in entries {
            if let mod = try? e.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: e)
            }
        }
    }
}

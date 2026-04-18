import Foundation
import SQLite3

/// Minimal read/write access to Cursor's global storage SQLite DB.
/// Uses prepared statements with sqlite3_bind_text (never manual escaping).
enum CursorSQLite {
    static var databaseURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Cursor", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb")
    }

    static func readValue(for key: String, at url: URL = databaseURL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle = db
        else {
            if let handle = db { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt
        else { return nil }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT is -1 cast to a destructor; use a constant.
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(statement, 0) else { return nil }
        let value = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @discardableResult
    static func writeValue(_ value: String, for key: String, at url: URL = databaseURL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let handle = db
        else {
            if let handle = db { sqlite3_close(handle) }
            return false
        }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt
        else { return false }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)

        return sqlite3_step(statement) == SQLITE_DONE
    }
}

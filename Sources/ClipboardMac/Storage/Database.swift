import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case text(String)
    case int(Int64)
    case blob(Data)
    case null
}

struct DatabaseError: Error, CustomStringConvertible {
    let message: String
    var description: String { "DatabaseError: \(message)" }
}

/// Thin wrapper over the system SQLite3 C API (no external dependencies).
final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db = db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(db)
            throw DatabaseError(message: message)
        }
        handle = db
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw DatabaseError(message: message)
        }
    }

    func run(_ sql: String, _ bindings: [SQLValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [[String: SQLValue]] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }

        var rows: [[String: SQLValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLValue] = [:]
            let columnCount = sqlite3_column_count(statement)
            for index in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .int(sqlite3_column_int64(statement, index))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, index) {
                        let count = Int(sqlite3_column_bytes(statement, index))
                        row[name] = .blob(Data(bytes: bytes, count: count))
                    } else {
                        row[name] = .null
                    }
                case SQLITE_FLOAT:
                    row[name] = .int(Int64(sqlite3_column_double(statement, index)))
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String, _ bindings: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement = statement else {
            throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let string):
                sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .int(let number):
                sqlite3_bind_int64(statement, index, number)
            case .blob(let data):
                data.withUnsafeBytes { buffer in
                    _ = sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }
}

// Convenience accessors for reading query results.
extension Dictionary where Key == String, Value == SQLValue {
    func string(_ key: String) -> String? {
        if case .text(let value)? = self[key] { return value }
        return nil
    }

    func int(_ key: String) -> Int64? {
        if case .int(let value)? = self[key] { return value }
        return nil
    }
}

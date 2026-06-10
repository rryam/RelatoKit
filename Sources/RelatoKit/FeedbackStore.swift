import Foundation
import SQLite3

public struct StoreTableCount: Equatable {
    public var table: String
    public var rows: Int
}

public struct ContentItemRow: Equatable {
    public var pk: String
    public var remoteID: String
    public var type: String
    public var updated: String
    public var title: String
    public var subtitle: String
}

public struct UploadTaskRow: Equatable {
    public var pk: String
    public var taskID: String
    public var state: String
    public var stage: String
    public var uploaded: String
    public var total: String
}

public struct FormStubRow: Equatable {
    public var topic: String
    public var tat: String
    public var platform: String
    public var description: String
}

public final class FeedbackStore {
    public static let defaultPath = "\(NSHomeDirectory())/Library/Group Containers/group.com.apple.feedback/Library/Application Support/feedback.sqlite"

    private let path: String

    public init(path: String = FeedbackStore.defaultPath) {
        self.path = NSString(string: path).expandingTildeInPath
    }

    public func summary() throws -> [StoreTableCount] {
        let tables = [
            "ZCONTENTITEM",
            "ZFEEDBACK",
            "ZFORMRESPONSE",
            "ZANSWER",
            "ZFILEPROMISE",
            "ZUPLOADTASK",
            "ZFEEDBACKFOLLOWUP",
            "ZTEAM",
            "ZUSER"
        ]
        return try withDatabase { db in
            try tables.map { table in
                StoreTableCount(table: table, rows: try db.scalarInt("SELECT count(*) FROM \(table)"))
            }
        }
    }

    public func contentItems(limit: Int = 20) throws -> [ContentItemRow] {
        try withDatabase { db in
            try db.rows(
                """
                SELECT Z_PK, ZREMOTEID, ZTYPE, ZUPDATEDAT,
                       COALESCE(ZTITLE, ''),
                       COALESCE(ZSUBTITLE, '')
                FROM ZCONTENTITEM
                ORDER BY ZUPDATEDAT DESC
                LIMIT ?
                """,
                bindings: [.int(limit)]
            ).map {
                ContentItemRow(pk: $0[0], remoteID: $0[1], type: $0[2], updated: $0[3], title: $0[4], subtitle: $0[5])
            }
        }
    }

    public func uploadTasks(limit: Int = 20) throws -> [UploadTaskRow] {
        try withDatabase { db in
            try db.rows(
                """
                SELECT Z_PK, ZTASKIDENTIFIER, ZTASKSTATE, ZLOCALSUBMISSIONSTAGE,
                       ZBYTESUPLOADED, ZBYTESTOUPLOAD
                FROM ZUPLOADTASK
                ORDER BY Z_PK DESC
                LIMIT ?
                """,
                bindings: [.int(limit)]
            ).map {
                UploadTaskRow(pk: $0[0], taskID: $0[1], state: $0[2], stage: $0[3], uploaded: $0[4], total: $0[5])
            }
        }
    }

    public func formStubs() throws -> [FormStubRow] {
        try withDatabase { db in
            try db.rows(
                """
                SELECT ZNAME, ZTAT, ZPLATFORM, COALESCE(ZFORMDESCRIPTION, '')
                FROM ZBUGFORMSTUB
                ORDER BY ZNAME
                """
            ).map {
                FormStubRow(topic: $0[0], tat: $0[1], platform: $0[2], description: $0[3])
            }
        }
    }

    private func withDatabase<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RelatoError.missingFile(path)
        }
        let db = try SQLiteDatabase(path: path)
        return try body(db)
    }
}

private enum SQLiteBinding {
    case int(Int)
    case text(String)
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let uri = URL(fileURLWithPath: path).absoluteString + "?mode=ro"
        let result = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
            throw RelatoError.sqlite(message)
        }
        try execute("PRAGMA query_only = ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw RelatoError.sqlite(message)
        }
    }

    func scalarInt(_ sql: String) throws -> Int {
        let values = try rows(sql)
        return Int(values.first?.first ?? "0") ?? 0
    }

    func rows(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RelatoError.sqlite(lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .int(let value):
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            }
        }

        var output: [[String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let count = sqlite3_column_count(statement)
                var row: [String] = []
                for column in 0..<count {
                    row.append(Self.stringValue(statement: statement, column: column))
                }
                output.append(row)
            } else if step == SQLITE_DONE {
                return output
            } else {
                throw RelatoError.sqlite(lastError)
            }
        }
    }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }

    private static func stringValue(statement: OpaquePointer?, column: Int32) -> String {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        case SQLITE_NULL:
            return ""
        default:
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

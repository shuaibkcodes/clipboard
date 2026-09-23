import Foundation

enum Migrations {
    static func run(on database: Database) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            preview TEXT,
            plain_text TEXT,
            source_app TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_pinned INTEGER DEFAULT 0,
            hash TEXT NOT NULL,
            file_path TEXT,
            thumbnail_path TEXT,
            metadata_json TEXT
        );
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS clipboard_item_formats (
            id TEXT PRIMARY KEY,
            clipboard_item_id TEXT NOT NULL,
            pasteboard_type TEXT NOT NULL,
            data_path TEXT,
            text_value TEXT,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (clipboard_item_id) REFERENCES clipboard_items(id)
        );
        """)

        try database.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_items_hash ON clipboard_items(hash);"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_updated ON clipboard_items(is_pinned, updated_at);"
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_formats_item ON clipboard_item_formats(clipboard_item_id);"
        )

        // v2: user-assigned tags, stored comma-separated.
        let columns = try database.query("PRAGMA table_info(clipboard_items);")
        if !columns.contains(where: { $0.string("name") == "tags" }) {
            try database.execute("ALTER TABLE clipboard_items ADD COLUMN tags TEXT;")
        }
    }
}

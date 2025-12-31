import Foundation
import GRDB

// MARK: - Storage Manager

public final class StorageManager: Sendable {
    public static let shared = StorageManager()

    private let dbQueue: DatabaseQueue

    private init() {
        // Initialize database in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let openRingDir = appSupport.appendingPathComponent("open-ring", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: openRingDir, withIntermediateDirectories: true)

        let dbPath = openRingDir.appendingPathComponent("open-ring.db").path

        do {
            dbQueue = try DatabaseQueue(path: dbPath)
            try migrate()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    // MARK: - Migrations

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            // Devices table
            try db.create(table: "devices") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("location", .text)
                t.column("capabilities_json", .text)
                t.column("firmware_version", .text)
                t.column("last_seen_at", .integer)
                t.column("created_at", .integer).defaults(sql: "(strftime('%s', 'now'))")
            }

            // Events table
            try db.create(table: "events") { t in
                t.column("id", .text).primaryKey()
                t.column("device_id", .text).notNull().references("devices", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("created_at", .integer).notNull()
                t.column("metadata_json", .text)
                t.column("ring_clip_id", .text)
                t.column("snapshot_path", .text)
                t.column("important", .integer).defaults(to: 0)
                t.column("processed_at", .integer)
            }

            // Clips table
            try db.create(table: "clips") { t in
                t.column("id", .text).primaryKey()
                t.column("device_id", .text).notNull().references("devices", onDelete: .cascade)
                t.column("event_id", .text).references("events", onDelete: .setNull)
                t.column("created_at", .integer).notNull()
                t.column("duration_seconds", .integer)
                t.column("ring_url", .text)
                t.column("local_path", .text)
                t.column("expires_at", .integer)
            }

            // Snapshots table
            try db.create(table: "snapshots") { t in
                t.column("id", .text).primaryKey()
                t.column("event_id", .text).references("events", onDelete: .setNull)
                t.column("device_id", .text).notNull().references("devices", onDelete: .cascade)
                t.column("path", .text).notNull()
                t.column("created_at", .integer).notNull()
                t.column("sha256", .text)
            }

            // Settings table
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }

            // Rules table
            try db.create(table: "rules") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("enabled", .integer).defaults(to: 1)
                t.column("predicate_lua", .text)
                t.column("action_lua", .text)
                t.column("last_triggered_at", .integer)
                t.column("created_at", .integer).defaults(sql: "(strftime('%s', 'now'))")
            }

            // Webhooks table
            try db.create(table: "webhooks") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("events_json", .text)
                t.column("headers_json", .text)
                t.column("enabled", .integer).defaults(to: 1)
                t.column("last_triggered_at", .integer)
                t.column("created_at", .integer).defaults(sql: "(strftime('%s', 'now'))")
            }

            // Indexes
            try db.create(index: "idx_events_device_created", on: "events", columns: ["device_id", "created_at"])
            try db.create(index: "idx_events_kind", on: "events", columns: ["kind"])
            try db.create(index: "idx_clips_device", on: "clips", columns: ["device_id", "created_at"])
        }

        // Migration v2: Add AI description column to events
        migrator.registerMigration("v2_ai_description") { db in
            try db.alter(table: "events") { t in
                t.add(column: "ai_description", .text)
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Settings

    public func getSetting(_ key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    public func setSetting(_ key: String, value: String?) throws {
        try dbQueue.write { db in
            if let value {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            } else {
                try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key])
            }
        }
    }
}

// MARK: - Settings Keys

public extension StorageManager {
    enum SettingKey: String {
        case snoozeUntil = "snooze_until"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case motionAlertsEnabled = "motion_alerts_enabled"
        case packageAlertsEnabled = "package_alerts_enabled"
        case defaultDeviceId = "default_device_id"
    }
}

// MARK: - Event Storage

public extension StorageManager {
    /// Save or update an event in the database
    func saveEvent(
        id: String,
        deviceId: String,
        kind: String,
        createdAt: Date,
        deviceName: String? = nil
    ) throws {
        try dbQueue.write { db in
            // First ensure device exists (minimal record)
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO devices (id, name, type)
                    VALUES (?, ?, 'unknown')
                """,
                arguments: [deviceId, deviceName ?? "Unknown"]
            )

            // Insert or update event
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO events (id, device_id, kind, created_at)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: [id, deviceId, kind, Int(createdAt.timeIntervalSince1970)]
            )
        }
    }

    /// Update AI description for an event
    func updateEventDescription(_ eventId: String, description: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE events SET ai_description = ? WHERE id = ?",
                arguments: [description, eventId]
            )
        }
    }

    /// Get recent events with their AI descriptions
    func getRecentEventsWithDescriptions(hours: Int = 24, limit: Int = 50) throws -> [StoredEvent] {
        let cutoff = Int(Date().timeIntervalSince1970) - (hours * 3600)

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.id, e.device_id, e.kind, e.created_at, e.ai_description, d.name as device_name
                FROM events e
                LEFT JOIN devices d ON e.device_id = d.id
                WHERE e.created_at > ?
                ORDER BY e.created_at DESC
                LIMIT ?
            """, arguments: [cutoff, limit])

            return rows.map { row in
                StoredEvent(
                    id: row["id"],
                    deviceId: row["device_id"],
                    kind: row["kind"],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row["created_at"] as Int)),
                    aiDescription: row["ai_description"],
                    deviceName: row["device_name"]
                )
            }
        }
    }

    /// Check if an event already has an AI description
    func hasDescription(eventId: String) throws -> Bool {
        try dbQueue.read { db in
            let description = try String.fetchOne(
                db,
                sql: "SELECT ai_description FROM events WHERE id = ?",
                arguments: [eventId]
            )
            return description != nil && !description!.isEmpty
        }
    }
}

// MARK: - Stored Event Model

public struct StoredEvent: Sendable {
    public let id: String
    public let deviceId: String
    public let kind: String
    public let createdAt: Date
    public let aiDescription: String?
    public let deviceName: String?

    public var kindDisplayName: String {
        switch kind {
        case "ding": return "Ring press"
        case "motion": return "Motion detected"
        case "on_demand": return "Live view"
        default: return kind
        }
    }
}

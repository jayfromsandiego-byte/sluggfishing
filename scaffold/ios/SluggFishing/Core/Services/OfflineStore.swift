import Foundation

/// MOAT #2 — the offline mirror. GRDB/SQLite. Sprint 3.
/// Content plane: locations, waypoints, species intel, stocking, approved reports.
/// Community plane: the report outbox.
final class OfflineStore {
    static let shared = OfflineStore()

    // TODO(S3): GRDB DatabaseQueue setup + migrations mirroring schema.sql subset
    // TODO(S3): syncContent() — pull deltas by updated_at on app open + 6h background
    // TODO(S4): enqueueReport(_:) — write locally FIRST, always succeeds offline
    // TODO(S4): flushOutbox() — BGTaskScheduler + background URLSession, exponential backoff
    // TODO(S3): Mapbox OfflineManager — "San Diego" region pack download w/ WiFi consent
}

import Foundation

/// Offline report queue — Sprint 4.
/// States: queued -> uploading -> submitted(pending moderation) -> live/rejected.
/// Nothing is ever lost because the signal died at the kelp line.
struct OutboxItem: Identifiable {
    enum State: String { case queued, uploading, submitted, failed }
    let id: UUID
    var report: CatchReport
    var photoLocalPaths: [String]
    var state: State
    var attempts: Int
}

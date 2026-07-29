import Foundation

/// Thin wrapper around supabase-swift. Sprint 1.
final class SupabaseService {
    static let shared = SupabaseService()
    // TODO(S1): init SupabaseClient with SUPABASE_URL / SUPABASE_ANON_KEY from Secrets.xcconfig
    // TODO(S1): signInWithApple()
    // TODO(S2): fetchLocations(updatedSince:) -> [FishingLocation]
    // TODO(S2): fetchWaypoints(updatedSince:) -> [Waypoint]
    // TODO(S4): submitReport(_:) + uploadPhoto(_:) (server strips EXIF)
    // TODO(S5): fetchStockingEvents(updatedSince:)
}

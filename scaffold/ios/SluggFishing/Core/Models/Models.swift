import Foundation
import CoreLocation

// Mirrors supabase/schema.sql. Keep in lockstep.

enum WaterType: String, Codable, CaseIterable, Identifiable {
    case freshwater, saltShore = "salt_shore", pier, bay, lake, offshore
    var id: String { rawValue }
    var label: String {
        switch self {
        case .freshwater: "Fresh"; case .saltShore: "Salt"; case .pier: "Piers"
        case .bay: "Bays"; case .lake: "Lakes"; case .offshore: "Offshore"
        }
    }
}

enum PrivacyLevel: String, Codable, CaseIterable { case exact, general, zone }
enum ReportStatus: String, Codable { case pending, approved, rejected, flagged }

struct FishingLocation: Codable, Identifiable {
    let id: Int64
    var name: String
    var slug: String
    var water: WaterType
    var latitude: Double
    var longitude: Double
    var description: String?
    var depthStructure: String?
    var accessNotes: String?
    var parking: String?
    var fees: String?
    var regulations: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// MOAT #1 — permanent curated waypoint. Never auto-generated.
struct Waypoint: Codable, Identifiable {
    let id: Int64
    var locationId: Int64?
    var name: String
    var latitude: Double
    var longitude: Double
    var type: String       // reef | kelp | wreck | drop | flat | jetty | hole
    var depthFt: Int?
    var notes: String?
}

struct Species: Codable, Identifiable {
    let id: Int64
    var commonName: String
    var iconKey: String?
}

struct CatchReport: Codable, Identifiable {
    let id: Int64
    var userId: UUID
    var locationId: Int64?
    var privacy: PrivacyLevel
    var speciesId: Int64?
    var lengthIn: Double?
    var weightLb: Double?
    var bait: String?
    var technique: String?
    var body: String?
    var caughtAt: Date?
    var status: ReportStatus
}

struct StockingEvent: Codable, Identifiable {
    let id: Int64
    var locationId: Int64
    var speciesId: Int64?
    var stockDate: Date
    var quantityLbs: Double?
    var source: String?
}

struct Conditions: Codable {
    var windMph: Double?
    var windDirection: String?
    var swellFt: Double?
    var swellPeriodS: Double?
    var tideNext: String?      // "High 1.8ft @ 6:42 PM"
    var waterTempF: Double?
    var moonPhase: String?
    var sunrise: Date?
    var sunset: Date?
    var fetchedAt: Date        // drives the offline "as of" badge
}

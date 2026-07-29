import Foundation

/// Live plane — free stack. Sprint 3. Never blocks the map.
/// Open-Meteo marine (wind/swell/water temp, no key) + NOAA CO-OPS tides + NDBC buoys.
/// Moon phase + sunrise/sunset computed on-device.
final class ConditionsService {
    static let shared = ConditionsService()

    func conditions(for lat: Double, _ lon: Double) async -> Conditions? {
        // TODO(S3): GET api.open-meteo.com/v1/forecast + marine-api.open-meteo.com/v1/marine
        // TODO(S3): NOAA CO-OPS predictions (station 9410170 San Diego Bay / 9410230 La Jolla)
        // TODO(S3): cache last result per location -> Conditions.fetchedAt drives stale badge
        nil
    }
}

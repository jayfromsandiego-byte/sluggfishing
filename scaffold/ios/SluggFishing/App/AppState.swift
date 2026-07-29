import Foundation

/// Global app state. Sprint 1: auth + connectivity. Sprint 5: entitlements.
@MainActor
final class AppState: ObservableObject {
    @Published var isOffline = false          // drives OfflineBanner + stale badges
    @Published var isSubscribed = false       // RevenueCat entitlement mirror (S5)
    @Published var hasAISAddOn = false        // V1.1
    @Published var activeLayer: WaterType = .saltShore

    // TODO(S1): NWPathMonitor -> isOffline
    // TODO(S1): Supabase auth session
    // TODO(S5): RevenueCat Purchases.shared.getCustomerInfo
}

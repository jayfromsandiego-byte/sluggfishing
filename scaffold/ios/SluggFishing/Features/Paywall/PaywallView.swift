import SwiftUI

/// Sprint 5 — RevenueCat. Free tier sees the map + waypoints (the wealth),
/// Pro unlocks depth: full spot intel, live conditions, offline packs,
/// stocking alerts, bite ratings. AIS boat tracking is the add-on tier (V1.1).
struct PaywallView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Fish smarter. Everywhere. Even offline.")
                .font(.title2.bold()).foregroundStyle(Theme.foam)
            // TODO(S5): RevenueCat offerings, $2.99/mo + annual anchor, AIS add-on upsell
            // TODO(S5): restore purchases + family-friendly cancel copy
        }
        .padding()
        .background(Theme.abyss)
    }
}

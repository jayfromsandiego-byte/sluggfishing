import SwiftUI

/// Offline is a STATE, not an error. The map, waypoints, and spot intel all still work.
struct OfflineBanner: View {
    var body: some View {
        Label("Offline — map + spots still work. Reports will send when you're back.",
              systemImage: "antenna.radiowaves.left.and.right.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.foam)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.surface)
            .clipShape(Capsule())
    }
}

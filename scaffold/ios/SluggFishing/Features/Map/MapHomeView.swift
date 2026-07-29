import SwiftUI

/// The core screen. Sprint 1 shell -> Sprint 2 real pins -> Sprint 3 offline packs.
struct MapHomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            // TODO(S1): MapboxMaps MapView (dark style), camera on San Diego
            Theme.deepWater.ignoresSafeArea()
            VStack(spacing: 12) {
                if appState.isOffline { OfflineBanner() }
                layerSwitcher
                Spacer()
            }
        }
    }

    /// The 6 water-type layers — one tap, thumb-reachable, glove-friendly targets.
    private var layerSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WaterType.allCases) { layer in
                    Button(layer.label) { appState.activeLayer = layer }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(appState.activeLayer == layer ? Theme.bite : Theme.surface)
                        .foregroundStyle(Theme.foam)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }
}

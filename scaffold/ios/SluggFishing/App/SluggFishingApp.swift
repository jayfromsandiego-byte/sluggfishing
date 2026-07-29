import SwiftUI

@main
struct SluggFishingApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MapHomeView()
                .environmentObject(appState)
                .preferredColorScheme(.dark) // dark-first: dawn launches + on-water glare
        }
    }
}

import SwiftUI

/// Location detail page — Sprint 2. Works fully offline (content plane).
/// Sections: bite rating, live conditions (stale badge offline), species+seasons,
/// baits/techniques, depth/structure, access/parking/fees/regulations,
/// stocking schedule (lakes), recent approved reports.
struct LocationDetailView: View {
    let location: FishingLocation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(location.name).font(.largeTitle.bold()).foregroundStyle(Theme.foam)
                // TODO(S2): species chips + season bars
                // TODO(S3): ConditionsModule(location:) with fetchedAt stale badge
                // TODO(S5): BiteRatingBadge + StockingScheduleCard (lakes)
                // TODO(S4): approved reports feed
            }
            .padding()
        }
        .background(Theme.deepWater)
    }
}

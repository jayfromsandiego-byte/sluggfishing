import SwiftUI

/// Report composer — Sprint 4. Writes to the outbox FIRST (always succeeds offline).
struct NewReportView: View {
    @State private var privacy: PrivacyLevel = .general

    var body: some View {
        Form {
            // TODO(S4): photo picker (compressed ~1600px), species, size, bait, notes
            Section("Location privacy") {
                Picker("Who sees where", selection: $privacy) {
                    Text("Exact spot").tag(PrivacyLevel.exact)
                    Text("General area (~1km)").tag(PrivacyLevel.general)
                    Text("Zone only").tag(PrivacyLevel.zone)
                }
                .pickerStyle(.segmented)
                Text("Your exact coordinates are never shown unless you choose Exact.")
                    .font(.caption).foregroundStyle(Theme.mist)
            }
            // TODO(S4): submit -> OfflineStore.shared.enqueueReport
        }
        .navigationTitle("New Report")
    }
}

import SwiftUI

/// The Settings screen — units and preferences. Profile, Apple Health, and About are separate
/// destinations in the side menu. Presented as a sheet from the drawer.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightInPounds") private var weightInPounds = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Units")
                            Toggle("Show weight in pounds", isOn: $weightInPounds).tint(BrandColor.accent)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Reminders")
                            Text("Dose reminders are set per protocol. Open a protocol to turn its reminder on and pick a time.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

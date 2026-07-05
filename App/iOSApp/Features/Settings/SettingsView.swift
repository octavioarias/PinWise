import SwiftUI

/// The Settings screen — units and preferences. Profile, Apple Health, and About are separate
/// destinations in the side menu. Presented as a sheet from the drawer.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightInPounds") private var weightInPounds = true

    /// Region hint — metric locales default to kg; US/UK-style locales to pounds for body weight.
    private var suggestsPounds: Bool { Locale.current.measurementSystem != .metric }
    private var suggestedUnitLabel: String { suggestsPounds ? "pounds (lb)" : "kilograms (kg)" }
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.dark.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Appearance")
                            Picker("Appearance", selection: $appearanceRaw) {
                                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Units")
                            FieldRow("Weight", hint: "Suggested for your region: \(suggestedUnitLabel).") {
                                Picker("Weight unit", selection: $weightInPounds) {
                                    Text("Pounds (lb)").tag(true)
                                    Text("Kilograms (kg)").tag(false)
                                }
                                .pickerStyle(.segmented)
                            }
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

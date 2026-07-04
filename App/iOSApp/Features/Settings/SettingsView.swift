import SwiftUI

/// Profile, units, health connections, and about — presented as a sheet from the Home menu.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profileName") private var name = ""
    @AppStorage("weightInPounds") private var weightInPounds = true
    @State private var health = HealthManager.shared
    @State private var requesting = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Profile")
                            FieldRow("Your name", hint: "Optional — used to personalize the app.") {
                                TextField("Name", text: $name).pinwiseField()
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Units")
                            Toggle("Show weight in pounds", isOn: $weightInPounds).tint(BrandColor.accent)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Health connections")
                            Text("PinWise can read weight, resting heart rate, and HRV from Apple Health to show them next to your dose logs. It's read-only and stays on your device.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                            connectRow
                            Divider().overlay(BrandColor.stroke)
                            Text("Oura, Whoop, and most wearables write to Apple Health. Connect Health above and their data flows in automatically — no separate login.")
                                .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Reminders")
                            Text("Dose reminders are set per protocol. Open a protocol to turn its reminder on and pick a time.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "About")
                            HStack {
                                Text("Version").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                                Spacer()
                                Text(appVersion).font(.caption).foregroundStyle(BrandColor.textSecondary)
                            }
                            Text("PinWise is for tracking and education. It doesn't provide medical advice, diagnosis, or treatment. Talk to a licensed clinician about your health decisions.")
                                .font(.caption2).foregroundStyle(BrandColor.textSecondary)
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

    @ViewBuilder private var connectRow: some View {
        if !health.isAvailable {
            Text("Health data isn't available on this device.")
                .font(.caption).foregroundStyle(BrandColor.textSecondary)
        } else if health.authorized {
            Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.success)
        } else {
            Button {
                Task { requesting = true; await health.requestAuthorization(); requesting = false }
            } label: {
                Label(requesting ? "Connecting…" : "Connect Apple Health", systemImage: "heart.text.square")
                    .font(.body.weight(.semibold)).foregroundStyle(BrandColor.accentText)
            }
            .buttonStyle(.plain).disabled(requesting)
        }
    }
}

import SwiftUI
import UIKit

/// The Settings hub. Presented as a sheet from the side menu. Sections: Account, Notifications,
/// Connections, Preferences, Security & Privacy, and Software Information.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightInPounds") private var weightInPounds = true
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.dark.rawValue
    @AppStorage(BiometricLock.prefKey) private var faceIDLock = false
    @AppStorage("shareHealthWithNatt") private var shareHealthWithNatt = false

    private var suggestsPounds: Bool { Locale.current.measurementSystem != .metric }
    private var suggestedUnitLabel: String { suggestsPounds ? "pounds (lb)" : "kilograms (kg)" }

    @State private var showMembership = false
    @State private var showConnections = false
    @State private var showLegal = false
    @State private var showBackupNote = false
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {

                    // ── Account ────────────────────────────────────────────────
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Account")
                            settingsRow("Manage membership", icon: "creditcard", detail: "Free trial") { showMembership = true }
                            Divider().overlay(BrandColor.stroke)
                            settingsRow("Back up all data", icon: "arrow.up.doc.on.clipboard") { showBackupNote = true }
                            Divider().overlay(BrandColor.stroke)
                            settingsRow("Export data (CSV)", icon: "square.and.arrow.up") { showExport = true }
                        }
                    }

                    // ── Notifications ──────────────────────────────────────────
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Notifications")
                            Text("Dose reminders are set per protocol — open a protocol to turn its reminder on and pick a time. System permission and delivery style are managed in iOS Settings.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            } label: {
                                Label("Open notification settings", systemImage: "bell.badge")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ── Connections (moved in from the side menu) ──────────────
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Connections")
                            settingsRow("Apple Health & devices", icon: "heart.text.square",
                                        detail: HealthManager.shared.authorized ? "Connected" : "Not connected") { showConnections = true }
                        }
                    }

                    // ── Preferences ────────────────────────────────────────────
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Preferences")
                            FieldRow("Appearance") {
                                Picker("Appearance", selection: $appearanceRaw) {
                                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                                }
                                .pickerStyle(.segmented)
                            }
                            FieldRow("Weight", hint: "Suggested for your region: \(suggestedUnitLabel).") {
                                Picker("Weight unit", selection: $weightInPounds) {
                                    Text("Pounds (lb)").tag(true)
                                    Text("Kilograms (kg)").tag(false)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }

                    // ── Security & Privacy ─────────────────────────────────────
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Security & Privacy")
                            if BiometricLock.isAvailable {
                                Toggle(isOn: faceIDBinding) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Unlock with \(BiometricLock.biometryName)")
                                            .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                                        Text("Off by default. When on, PinWise asks for \(BiometricLock.biometryName) each time you open it.")
                                            .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                                    }
                                }
                                .tint(BrandColor.accent)
                                Divider().overlay(BrandColor.stroke)
                            }
                            Toggle(isOn: $shareHealthWithNatt) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share Apple Health with Natt")
                                        .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                                    Text("Off by default. When on, the Apple Health metrics PinWise reads (weight, resting heart rate, HRV, sleep, steps) are sent to the assistant so it can personalize answers. Requires Apple Health connected; turn off anytime.")
                                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                            .tint(BrandColor.accent)
                            Divider().overlay(BrandColor.stroke)
                            settingsRow("Privacy Policy & Terms of Service", icon: "doc.text") { showLegal = true }
                        }
                    }

                    // ── Software Information ───────────────────────────────────
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Software Information")
                            infoRow("App version", appVersion)
                            infoRow("iOS version", systemVersion)
                            infoRow("Device", deviceModel)
                            Text("PinWise is for tracking and education — not medical advice, diagnosis, or treatment. Talk to a licensed clinician about your health decisions.")
                                .font(.caption2).foregroundStyle(BrandColor.textSecondary).padding(.top, Space.xs)
                        }
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showMembership) { MembershipView() }
            .sheet(isPresented: $showConnections) { HealthConnectionsView() }
            .sheet(isPresented: $showLegal) { LegalDocumentView() }
            .sheet(isPresented: $showExport) { DataExportView() }
            .alert("Backup isn't available yet", isPresented: $showBackupNote) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Your data is stored on this device. Cloud backup arrives with account sync — you'll be able to back up and restore across devices then.")
            }
        }
    }

    /// Enabling the lock requires passing a biometric check first; a failed/canceled prompt leaves it off.
    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { faceIDLock },
            set: { on in
                guard on else { faceIDLock = false; return }
                Task {
                    faceIDLock = await BiometricLock.authenticate(
                        reason: "Turn on \(BiometricLock.biometryName) so PinWise locks when you're away")
                }
            }
        )
    }

    // MARK: - Software info
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
    private var systemVersion: String { "iOS \(UIDevice.current.systemVersion)" }
    private var deviceModel: String { UIDevice.current.model }

    // MARK: - Rows
    private func settingsRow(_ title: String, icon: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: icon).font(.body).frame(width: 24).foregroundStyle(BrandColor.accentText)
                Text(title).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(BrandColor.textSecondary) }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
            Spacer()
            Text(value).font(.caption).foregroundStyle(BrandColor.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

/// Membership / subscription management. Placeholder until StoreKit lands — it shows the plans and
/// where status will appear; the live trial/monthly/yearly state wires in with the subscription build.
struct MembershipView: View {
    var body: some View {
        MenuSheet(title: "Membership") {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Your plan")
                    HStack {
                        Text("Status").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                        Spacer()
                        Text("Free trial").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                    }
                    Text("Subscriptions aren't live yet — this is where you'll see whether you're on the free trial, monthly, or yearly plan, and manage or cancel it, once they're enabled.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionHeader(title: "Plans")
                    planRow("Monthly", "$7.99 / month")
                    planRow("Yearly", "$39.99 / year")
                    Text("A 3-week free trial starts you off. After the trial, a subscription keeps the app and Natt unlocked.")
                        .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    private func planRow(_ name: String, _ price: String) -> some View {
        HStack {
            Text(name).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
            Spacer()
            Text(price).font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
        }
    }
}

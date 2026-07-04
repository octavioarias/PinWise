import SwiftUI

/// Compact health snapshot shown at the top of the Tools tab. Surfaces the three signals most
/// worth watching alongside a dosing protocol — body weight, resting heart rate, and HRV —
/// or a connect prompt if Apple Health isn't linked yet. Read-only; stays on device.
struct HealthWidget: View {
    @State private var health = HealthManager.shared
    @State private var requesting = false
    @AppStorage("weightInPounds") private var weightInPounds = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Label("Health", systemImage: "heart.fill")
                        .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Spacer()
                    if health.authorized {
                        Button { Task { await health.refresh() } } label: {
                            Image(systemName: "arrow.clockwise").foregroundStyle(BrandColor.accentText)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Refresh health data")
                    }
                }

                if !health.isAvailable {
                    Text("Health data isn't available on this device.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                } else if health.authorized {
                    Text("Signals worth watching alongside your doses.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    HStack(spacing: Space.md) {
                        metric("Weight (\(weightInPounds ? "lb" : "kg"))", weightText, "scalemass")
                        Divider().frame(height: 40).overlay(BrandColor.stroke)
                        metric("Resting HR (bpm)", hrText, "heart")
                        Divider().frame(height: 40).overlay(BrandColor.stroke)
                        metric("HRV (ms)", hrvText, "waveform.path.ecg")
                    }
                } else {
                    Text("Connect Apple Health to see weight, resting heart rate, and HRV next to your logs. Data from Oura, Whoop, and similar wearables shows up here too. Nothing leaves your device.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    Button {
                        Task { requesting = true; await health.requestAuthorization(); requesting = false }
                    } label: {
                        Label(requesting ? "Connecting…" : "Connect Apple Health", systemImage: "heart.text.square")
                            .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
                    }
                    .buttonStyle(.plain).disabled(requesting)
                }
            }
        }
        .task { if health.authorized { await health.refresh() } }
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2).tracking(0.5).foregroundStyle(BrandColor.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(Typo.numberMD).foregroundStyle(BrandColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weightText: String {
        guard let kg = health.latestWeightKg else { return "—" }
        return String(format: "%.1f", weightInPounds ? kg * 2.20462 : kg)
    }
    private var hrText: String { health.restingHeartRate.map { String(Int($0.rounded())) } ?? "—" }
    private var hrvText: String { health.hrvMilliseconds.map { String(Int($0.rounded())) } ?? "—" }
}

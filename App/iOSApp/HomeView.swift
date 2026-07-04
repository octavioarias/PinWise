import SwiftUI
import SwiftData
import PeptideKit

/// The dashboard. Reflects real logged activity from SwiftData and routes the quick actions
/// to the right tabs. Adherence/next-dose arrive once protocols exist; for now it surfaces
/// what's genuinely known: recent doses, weekly count, and site rotation.
struct HomeView: View {
    @Binding var selected: AppTab
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]

    private var lastDose: LoggedDose? { recent.first }
    private var thisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return recent.filter { $0.timestamp >= weekAgo }.count
    }
    private var sitesInRotation: Int { Set(recent.prefix(30).compactMap { $0.site }).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    quickActions
                    if recent.isEmpty { emptyState } else { atAGlance; recentSection }
                    DisclaimerBanner(text: Disclaimer.calculator)
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("PinWise")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Track your protocol.\nKnow the science.")
                .font(Typo.displayL)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text("The source of truth for peptides and dose tracking — transparent about where the evidence stands.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        HStack(spacing: Space.md) {
            QuickAction(title: "Log a dose", systemImage: "plus.circle.fill") { selected = .log }
            QuickAction(title: "Reconstitution", systemImage: "syringe.fill") { selected = .tools }
        }
    }

    private var atAGlance: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "At a glance")
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack {
                        StatTile(label: "Logged this week", value: "\(thisWeekCount)", emphasized: true)
                        Divider().frame(height: 40).overlay(BrandColor.stroke)
                        StatTile(label: "Sites in rotation", value: "\(sitesInRotation)")
                    }
                    if let l = lastDose {
                        Divider().overlay(BrandColor.stroke)
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LAST DOSE").font(Typo.caption).tracking(0.8).foregroundStyle(BrandColor.textSecondary)
                                Text("\(l.compoundName) · \(l.dose.displayString)")
                                    .font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                            }
                            Spacer()
                            Text(l.timestamp, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Recent")
            ForEach(Array(recent.prefix(5)), id: \.id) { entry in
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.compoundName).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                            Text(entry.dose.displayString + (entry.site.map { " · \($0.displayName)" } ?? ""))
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        }
                        Spacer()
                        Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Get started")
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Log your first dose")
                        .font(Typo.headline)
                        .foregroundStyle(BrandColor.textPrimary)
                    Text("Tap below (or the ＋ in the tab bar) to record a dose. Everything stays on your device.")
                        .font(Typo.body)
                        .foregroundStyle(BrandColor.textSecondary)
                    PrimaryButton(title: "Log a dose", systemImage: "plus") { selected = .log }
                        .padding(.top, Space.sm)
                }
            }
        }
    }
}

/// A tappable quick-action tile.
private struct QuickAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(BrandColor.accentText)
                Text(title)
                    .font(Typo.headline)
                    .foregroundStyle(BrandColor.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(Space.lg)
            .background(
                LinearGradient(colors: [BrandColor.surface, BrandColor.surfaceElevated.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(BrandColor.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

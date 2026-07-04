import SwiftUI
import SwiftData
import PeptideKit

/// The dashboard. Reflects real logged activity and — once protocols exist — a live
/// adherence ring and next-dose, computed with the verified PeptideKit logic.
struct HomeView: View {
    @Binding var selected: AppTab
    @Binding var showMenu: Bool
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var lastDose: LoggedDose? { recent.first }
    private var thisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return recent.filter { $0.timestamp >= weekAgo }.count
    }
    private var sitesInRotation: Int { Set(recent.prefix(30).compactMap { $0.site }).count }

    /// Aggregate adherence over the last 14 days across active protocols.
    private var adherenceFraction: Double {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: end)) ?? end
        var expected = 0, taken = 0
        for p in activeProtocols {
            let logDates = recent.filter { $0.compoundName == p.compoundName }.map(\.timestamp)
            let r = AdherenceCalculator.evaluate(schedule: p.schedule,
                                                 start: max(start, cal.startOfDay(for: p.startDate)),
                                                 end: end, logDates: logDates, calendar: cal)
            expected += r.expectedCount
            taken += r.takenCount
        }
        return expected == 0 ? 0 : Double(taken) / Double(expected)
    }
    private var nextDoseDate: Date? { activeProtocols.compactMap { $0.nextDose() }.min() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    quickActions
                    if !activeProtocols.isEmpty {
                        glanceWithRing
                    } else if !recent.isEmpty {
                        activityGlance
                    } else {
                        emptyState
                    }
                    if !recent.isEmpty { recentSection }
                    DisclaimerBanner(text: Disclaimer.calculator)
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BrandColor.textPrimary)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menu — profile, settings, and health connections")

            Text("Track your protocol.\nKnow the science.")
                .font(Typo.displayL).textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7).lineLimit(2)
            Text("The source of truth for peptides and dose tracking — transparent about where the evidence stands.")
                .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        HStack(spacing: Space.md) {
            QuickAction(title: "Log a dose", systemImage: "plus.circle.fill") { selected = .log }
            QuickAction(title: "Reconstitution", systemImage: "syringe.fill") { selected = .tools }
        }
    }

    private var glanceWithRing: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "At a glance")
            Card {
                HStack(spacing: Space.lg) {
                    AdherenceRing(fraction: adherenceFraction)
                    VStack(alignment: .leading, spacing: Space.md) {
                        labeledStat("Next dose", nextDoseText)
                        labeledStat("Logged this week", "\(thisWeekCount)")
                    }
                    Spacer()
                }
            }
        }
    }

    private var activityGlance: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "At a glance")
            Card {
                HStack {
                    StatTile(label: "Logged this week", value: "\(thisWeekCount)", emphasized: true)
                    Divider().frame(height: 40).overlay(BrandColor.stroke)
                    StatTile(label: "Sites in rotation", value: "\(sitesInRotation)")
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
                    Text("Log your first dose").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text("Tap below (or the ＋ in the tab bar) to record a dose. Everything stays on your device.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    PrimaryButton(title: "Log a dose", systemImage: "plus") { selected = .log }
                        .padding(.top, Space.sm)
                }
            }
        }
    }

    private var nextDoseText: String {
        guard let d = nextDoseDate else { return "—" }
        return d.formatted(.dateTime.weekday(.abbreviated).month().day())
    }

    private func labeledStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Typo.caption).tracking(0.8).foregroundStyle(BrandColor.textSecondary)
            Text(value).font(Typo.numberMD).foregroundStyle(BrandColor.textPrimary)
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
                Image(systemName: systemImage).font(.title2).foregroundStyle(BrandColor.accentText)
                Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(Space.lg)
            .background(
                LinearGradient(colors: [BrandColor.surface, BrandColor.surfaceElevated.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

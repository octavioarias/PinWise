import SwiftUI
import SwiftData

/// The five app sections. Order is deliberate: Log sits in the center to make logging a
/// dose the most reachable action.
enum AppTab: Hashable {
    case home, tools, log, protocols, news
}

/// Root shell with a compact custom bottom bar. All tabs are the same size and baseline;
/// the center Log tab is emphasized only through color + fill + a soft glow (never size or
/// vertical offset), so the bar stays standard-height and aligned.
struct RootTabView: View {
    @State private var selected: AppTab = .home
    @Query(sort: \SavedProtocol.startDate) private var protocols: [SavedProtocol]

    /// Changes whenever a reminder-relevant field changes, re-triggering scheduling.
    private var reminderSignature: String {
        protocols.map { "\($0.id.uuidString)|\($0.remindersOn)|\($0.isActive)|\($0.reminderHour):\($0.reminderMinute)|\($0.scheduleKindRaw)|\($0.intervalDays)|\($0.weekdays)" }.joined()
    }

    var body: some View {
        Group {
            switch selected {
            case .home: HomeView(selected: $selected)
            case .tools: ReconstitutionCalculatorView()
            case .log: LogView()
            case .protocols: ProtocolsView()
            case .news: NewsView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PinWiseTabBar(selected: $selected)
        }
        .tint(BrandColor.accent)
        .preferredColorScheme(.dark)
        .edgeGlow() // ambient accent glow around the screen edges
        .task(id: reminderSignature) {
            await NotificationManager.reschedule(protocols: protocols)
        }
    }
}

/// Compact bottom bar — a solid, elevated dark surface flush to the screen's bottom edge.
/// Five equal, center-aligned tabs; Log is a filled accent chip with a white glyph so it
/// stays high-contrast on any background without changing size or leaving the row.
private struct PinWiseTabBar: View {
    @Binding var selected: AppTab

    // A fixed icon-row height keeps every tab (including the Log chip) on one baseline.
    private let iconRow: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tab(.home, icon: "house.fill", label: "Home")
            tab(.tools, icon: "function", label: "Tools")
            tab(.log, icon: "plus", label: "Log", prominent: true)
            tab(.protocols, icon: "list.bullet.rectangle", label: "Protocols")
            tab(.news, icon: "newspaper.fill", label: "News")
        }
        .padding(.top, Space.md)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity)
        .background {
            BrandColor.surface
                .overlay(alignment: .top) {
                    LinearGradient(colors: [BrandColor.accent.opacity(0.12), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .overlay(alignment: .top) { Rectangle().fill(BrandColor.stroke).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom) // fill flush to the bottom, under the home indicator
        }
        .shadow(color: .black.opacity(0.5), radius: 14, y: -3) // lift it off the content
    }

    @ViewBuilder
    private func tab(_ item: AppTab, icon: String, label: String, prominent: Bool = false) -> some View {
        let isSelected = selected == item
        Button {
            selected = item
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if prominent {
                        Circle()
                            .fill(LinearGradient(colors: [BrandColor.accent, BrandColor.accent.opacity(0.85)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 30, height: 30)
                            .shadow(color: BrandColor.accent.opacity(0.55), radius: 6)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? BrandColor.accentText : BrandColor.textSecondary)
                    }
                }
                .frame(height: iconRow)
                Text(label)
                    .font(.system(size: 10, weight: prominent ? .bold : .medium))
                    .foregroundStyle(prominent || isSelected ? BrandColor.accentText : BrandColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Themed placeholder for sections not yet built out.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.md) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(BrandColor.accentText)
                Text(title).font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                Text(subtitle)
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .heroScreen()
            .navigationTitle(title)
        }
    }
}

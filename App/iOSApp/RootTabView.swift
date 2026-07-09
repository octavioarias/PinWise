import SwiftUI
import SwiftData

/// The five app sections. Order is deliberate: Log sits in the center to make logging a
/// dose the most reachable action.
enum AppTab: Hashable {
    case home, tools, log, protocols, news
}

/// Root shell with a floating glass tab bar. Four tabs share one quiet monochrome
/// register; the center Log tab is the deliberate exception (a Strava-style record
/// button): larger, crested above the capsule's top edge, and the only color in the chrome.
struct RootTabView: View {
    @State private var selected: AppTab = .home
    @State private var showMenu = false
    @State private var showAssistant = false
    @Query(sort: \SavedProtocol.startDate) private var protocols: [SavedProtocol]
    @Query private var vials: [StoredVial]

    /// Changes whenever a reminder-relevant field changes, re-triggering scheduling.
    private var reminderSignature: String {
        protocols.map { "\($0.id.uuidString)|\($0.remindersOn)|\($0.isActive)|\($0.reminderHour):\($0.reminderMinute)|\($0.scheduleKindRaw)|\($0.intervalDays)|\($0.weekdays)" }.joined()
    }

    var body: some View {
        Group {
            switch selected {
            case .home: HomeView(selected: $selected, showMenu: $showMenu, showAssistant: $showAssistant)
            case .tools: ToolsView()
            case .log: LogView()
            case .protocols: ProtocolsView()
            case .news: NewsView()
            }
        }
        .overlay(alignment: .bottom) {
            PinWiseTabBar(selected: $selected)
        }
        // Drawers sit above the tab bar so they cover the full screen when open.
        .overlay {
            SideMenuDrawer(isOpen: $showMenu)
        }
        .overlay {
            AssistantDrawer(isOpen: $showAssistant)
        }
        .tint(BrandColor.accent)
        .task(id: reminderSignature) {
            await NotificationManager.reschedule(protocols: protocols, vials: vials)
        }
    }
}

/// Floating glass island — a brand-tinted ultra-thin-material capsule inset from the
/// screen edges (Space.lg gutters, Space.sm above the safe-area bottom), with scroll
/// content passing visibly beneath it. Five equal-width, center-aligned tabs; Log is a
/// flat accent disc with a white glyph that crests above the capsule's top edge —
/// visual emphasis only.
private struct PinWiseTabBar: View {
    @Binding var selected: AppTab

    // A fixed icon-row height keeps every tab (including the Log chip) on one baseline.
    private let iconRow: CGFloat = 30
    // The Log disc's diameter. It overflows the 30pt icon row and is offset upward by
    // half the difference, so the disc's top sits (chipSize - iconRow) above the column —
    // the crest offset AND the hit-region extension both derive from these two constants.
    private let chipSize: CGFloat = 44

    // Haptic trigger for ACTUAL taps only. `selected` also changes programmatically
    // (post-save auto-return Home, stackCard deep link) and those must not buzz.
    @State private var tapCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tab(.home, icon: "house.fill", label: "Home")
            tab(.tools, icon: "function", label: "Tools")
            tab(.log, icon: "plus", label: "Log", prominent: true)
            tab(.protocols, icon: "square.stack.3d.up.fill", label: "Stack")
            tab(.news, icon: "newspaper.fill", label: "News")
        }
        // Inner Space.md sides so the Home/News end columns clear the capsule's end radii.
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
        .padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity)
        // Glass recipe, rim → tint → blur: later .background modifiers stack BEHIND earlier
        // ones, so the 0.5pt capsule rim draws frontmost (a background, not an overlay, so
        // the crested Log disc covers it), the brand tint sits in front of the blur, and
        // content still shimmers through the material underneath. No clipShape anywhere —
        // background(_:in:) shapes the fills without decapitating the crested chip. The bar
        // is a bottom overlay floating Space.sm above the safe-area bottom inside Space.lg
        // gutters; scrolling content passes visibly beneath the glass, and the
        // tabBarClearance margin (derivation in Theme.swift) governs only where content
        // rests when scrolled to the end — not a hard stop at the bar's top edge.
        .background { Capsule().strokeBorder(BrandColor.stroke, lineWidth: 0.5) }
        .background(BrandColor.background.opacity(0.55), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        // Flatten to one silhouette BEFORE the shadow so it follows the capsule plus the
        // protruding crest arc instead of haloing each icon. (compositingGroup, never
        // drawingGroup — Metal rasterization kills the material's backdrop sampling.)
        .compositingGroup()
        .elevation(.chrome)
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.sm)
        .sensoryFeedback(.selection, trigger: tapCount)
    }

    @ViewBuilder
    private func tab(_ item: AppTab, icon: String, label: String, prominent: Bool = false) -> some View {
        let isSelected = selected == item
        Button {
            selected = item
            tapCount += 1
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if prominent {
                        Circle()
                            .fill(BrandColor.accent)
                            .frame(width: chipSize, height: chipSize)
                            .shadow(color: BrandColor.accent.opacity(0.4), radius: 12, y: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? BrandColor.textPrimary : BrandColor.textSecondary)
                    }
                }
                .frame(height: iconRow)
                // Offset AFTER the frame: the disc keeps its 30pt layout slot — so the
                // bar's content height feeding the tabBarClearance derivation in
                // Theme.swift is unchanged — but visually crests above the capsule's
                // top edge together with its glyph.
                .offset(y: prominent ? -(chipSize - iconRow) / 2 : 0)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? BrandColor.textPrimary : BrandColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            // The hit region must follow the drawn disc, not the layout slot: the crested
            // chip's top (chipSize - iconRow) sits above the column rect, and a plain
            // Rectangle would leave that upper arc of the primary CTA silently untappable.
            .contentShape(TabHitShape(topExtension: prominent ? chipSize - iconRow : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item == .log ? "Log a dose" : label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tab column's hit region: the column rect, optionally extended upward so the crested
/// Log chip's full disc is tappable. `topExtension: 0` is exactly a plain Rectangle, which
/// keeps one shape type across all five tabs (no view branching in the Button label).
private struct TabHitShape: Shape {
    var topExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - topExtension,
                    width: rect.width, height: rect.height + topExtension))
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

import SwiftUI
import SwiftData
import PeptideKit

/// The unified protocol card — the Stack tab's read on a `SavedProtocol` at a glance.
///
/// Reads top-to-bottom as an instrument: a status line (the dot's color IS the state),
/// the protocol name and contents, a 3-up DOSE / CADENCE / NEXT PIN stat grid, and —
/// when the protocol is linked to a vial — the same supply bar the inventory's `VialRow`
/// uses, so "how much is left" reads identically everywhere. Paused protocols dim the
/// card's content to 0.55 *inside* the card (callers must not dim again). Press feedback
/// comes from the caller's `PressableStyle` Button; entrance stagger via `.entrance(i)`.
struct ProtocolCard: View {
    let proto: SavedProtocol
    /// Vial-linked supply readout; nil when the protocol has no linked vial (row omitted).
    var supply: SupplyInfo?

    /// The caller resolves the protocol's vial linkage into this — the card stays a pure renderer.
    struct SupplyInfo {
        let fraction: Double
        let dosesLeft: Int
        let total: Int
        let needsReorder: Bool
    }

    private var status: SavedProtocol.DisplayStatus { proto.displayStatus }

    private var statusColor: Color {
        switch status {
        case .active: return BrandColor.success
        case .dueToday: return BrandColor.warning
        case .paused: return BrandColor.textSecondary
        }
    }

    private var statusLabel: String {
        switch status {
        case .active: return "Active"
        case .dueToday: return "Due today"
        case .paused: return "Paused"
        }
    }

    /// Next-pin display: "Today" (warning-tinted), "Tomorrow", an abbreviated date, or "—"
    /// when nothing is scheduled (as-needed protocols / no upcoming date).
    private var nextPin: (text: String, isToday: Bool) {
        guard let next = proto.nextDose() else { return ("—", false) }
        let calendar = Calendar.current
        if calendar.isDateInToday(next) { return ("Today", true) }
        if calendar.isDateInTomorrow(next) { return ("Tomorrow", false) }
        return (next.formatted(.dateTime.month(.abbreviated).day()), false)
    }

    private var accessibilityValueText: String {
        var value = "\(statusLabel), dose \(proto.effectiveDose.displayString), \(proto.cadenceText), next pin \(nextPin.text)"
        if let supply {
            value += ", \(supply.dosesLeft) of \(supply.total) doses left"
        }
        return value
    }

    var body: some View {
        Card(style: .standard) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    StatusDot(color: statusColor, glows: status != .paused)
                    MicroLabel(statusLabel, color: statusColor)
                    Spacer()
                    if proto.isStack { TagChip(text: "Blend", color: BrandColor.accentText) }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                }

                Text(proto.name)
                    .font(Typo.headline)
                    .foregroundStyle(BrandColor.textPrimary)

                // Contents meta — omitted when it would just repeat the name.
                if proto.contentsSummary != proto.name {
                    Text(proto.contentsSummary)
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }

                Rectangle()
                    .fill(BrandColor.stroke.opacity(0.6))
                    .frame(height: 1)

                HStack(alignment: .top, spacing: Space.md) {
                    ProtocolStat(label: "Dose", value: proto.effectiveDose.displayString,
                                 tint: BrandColor.accentText)
                    ProtocolStat(label: "Cadence", value: proto.cadenceText, compresses: true)
                    ProtocolStat(label: "Next pin", value: nextPin.text,
                                 tint: nextPin.isToday ? BrandColor.warning : BrandColor.textPrimary)
                }

                if let supply {
                    ProtocolSupplyRow(supply: supply)
                }
            }
            .opacity(status == .paused ? 0.55 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(proto.isStack ? "\(proto.name), blend" : proto.name)
        .accessibilityValue(accessibilityValueText)
    }
}

/// One column of the card's 3-up stat grid: a micro-label over a `Typo.statValue` figure.
private struct ProtocolStat: View {
    let label: String
    let value: String
    var tint: Color = BrandColor.textPrimary
    /// Cadence strings ("Mon, Wed, Fri") can run long — let them shrink instead of wrap.
    var compresses: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            MicroLabel(label)
            Text(value)
                .font(Typo.statValue)
                .foregroundStyle(tint)
                .lineLimit(compresses ? 1 : nil)
                .minimumScaleFactor(compresses ? 0.8 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The card's vial-supply readout — the same bar and thresholds as the inventory's
/// `VialRow`, so supply reads identically across the Stack tab's two panels.
private struct ProtocolSupplyRow: View {
    let supply: ProtocolCard.SupplyInfo

    // Mirrors VialRow.barColor exactly: reorder → danger, under half → warning, else success.
    private var barColor: Color {
        if supply.needsReorder { return BrandColor.danger }
        if supply.fraction < 0.5 { return BrandColor.warning }
        return BrandColor.success
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            ProgressView(value: supply.fraction).tint(barColor)
            Text("\(supply.dosesLeft) of \(supply.total) doses left")
                .font(.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .layoutPriority(1)
            if supply.needsReorder {
                TagChip(text: "Low", color: BrandColor.danger)
            }
        }
    }
}

extension SavedProtocol {
    /// The app-wide status vocabulary for a protocol: paused (inactive), due today, or
    /// active. Every surface that renders a protocol's status dot derives from this one
    /// read so the color language never forks between Home and the Stack tab.
    enum DisplayStatus { case active, dueToday, paused }

    var displayStatus: DisplayStatus {
        guard isActive else { return .paused }
        if let next = nextDose(), Calendar.current.isDateInToday(next) { return .dueToday }
        return .active
    }
}

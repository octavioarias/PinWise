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
    /// Full compound scope for the contents line — expands blend vials to every compound they
    /// hold. Caller resolves it (it needs the vials); nil falls back to the primary-only
    /// `proto.contentsSummary` so any caller without vials still renders.
    var contents: String?
    /// The unit to show the dose in — follows the linked vial's choice (caller resolves it). nil
    /// falls back to the auto mg/mcg display for callers without vials.
    var doseUnit: MassUnit?
    /// True when any linked vial is itself a blend (multiple compounds in ONE vial = one injection).
    /// Distinct from `proto.isStack` (multiple vials = multiple injections). Caller resolves it.
    var isBlend: Bool = false

    private var contentsText: String { contents ?? proto.contentsSummary }
    private var doseText: String {
        doseUnit.map { proto.effectiveDose.displayString(in: $0) } ?? proto.effectiveDose.displayString
    }

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
        var value = "\(statusLabel), dose \(doseText), \(proto.cadenceText), next pin \(nextPin.text)"
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
                    // A single blend vial (one shot, several compounds) = "Blend"; several vials
                    // (several injections) = "Stack". Previously both read "Blend", inverting it.
                    if isBlend { TagChip(text: "Blend", color: BrandColor.accentText) }
                    else if proto.isStack { TagChip(text: "Stack", color: BrandColor.accentText) }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                }

                Text(proto.name)
                    .font(Typo.headline)
                    .foregroundStyle(BrandColor.textPrimary)

                // Contents meta — full compound scope (blend vials expanded); omitted when it
                // would just repeat the name.
                if contentsText != proto.name {
                    Text(contentsText)
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }

                Rectangle()
                    .fill(BrandColor.stroke.opacity(0.6))
                    .frame(height: 1)

                HStack(alignment: .top, spacing: Space.md) {
                    ProtocolStat(label: "Dose", value: doseText,
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
        .accessibilityLabel(isBlend ? "\(proto.name), blend" : proto.isStack ? "\(proto.name), stack" : proto.name)
        .accessibilityValue(accessibilityValueText)
    }
}

/// One column of the card's 3-up stat grid: a micro-label over a `Typo.statValue` figure.
private struct ProtocolStat: View {
    let label: String
    let value: String
    var tint: Color = BrandColor.textPrimary
    /// Cadence can run long (a run of weekday letters, or "Every 3 days"). Let it wrap to a
    /// second line at full size — fitting the days — and only shrink as a last resort, rather
    /// than truncating on one line. The grid's `.top` alignment absorbs the taller column.
    var compresses: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            MicroLabel(label)
            Text(value)
                .font(Typo.statValue)
                .foregroundStyle(tint)
                .lineLimit(compresses ? 2 : nil)
                .minimumScaleFactor(compresses ? 0.8 : 1)
                .fixedSize(horizontal: false, vertical: true)
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

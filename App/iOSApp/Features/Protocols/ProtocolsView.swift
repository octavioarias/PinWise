import SwiftUI
import SwiftData
import PeptideKit

/// The Stack tab: your vials and your protocols (a "Your vials / Your protocols" segmented
/// control, vials default), plus a link into the compound library under Your vials.
struct ProtocolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var logs: [LoggedDose]
    @State private var showBuilder = false
    @State private var editTarget: EditTarget?
    @State private var panel: Panel = .inventory   // vials lead — protocols schedule from them
    private enum Panel: Hashable { case inventory, protocols }
    /// Identifiable wrapper so a tapped protocol can drive `.sheet(item:)` without relying on
    /// the model's own identity semantics.
    private struct EditTarget: Identifiable { let id = UUID(); let proto: SavedProtocol }

    private var active: [SavedProtocol] { protocols.filter(\.isActive) }
    private var inactive: [SavedProtocol] { protocols.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header

                    Picker("", selection: $panel) {
                        Text("Your vials").tag(Panel.inventory)
                        Text("Your protocols").tag(Panel.protocols)
                    }
                    .pickerStyle(.segmented)

                    if panel == .protocols {
                        protocolsPanel
                    } else {
                        InventoryList()
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .scrollsToTopOnReselect(.protocols)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showBuilder) { ProtocolBuilderView() }
            .sheet(item: $editTarget) { ProtocolBuilderView(editing: $0.proto) }
            // Consume a one-shot deep-link (e.g. Home's "Your protocols" card) targeting a panel.
            .onAppear {
                if UserDefaults.standard.string(forKey: "stackRequestedPanel") == "protocols" {
                    panel = .protocols
                    UserDefaults.standard.removeObject(forKey: "stackRequestedPanel")
                }
            }
        }
    }

    @ViewBuilder private var protocolsPanel: some View {
        if vials.isEmpty {
            // Protocols are built from vials — route vial-less users to the right first step.
            PrimaryButton(title: "Add a vial first", systemImage: "cross.vial") { panel = .inventory }
        } else {
            PrimaryButton(title: "New protocol", systemImage: "plus") { showBuilder = true }
        }

        if active.isEmpty {
            emptyState
        } else {
            SectionHeader(title: "Active protocols")
            ForEach(Array(active.enumerated()), id: \.element.id) { i, proto in
                let supplyInfo = supply(for: proto)
                Button { editTarget = EditTarget(proto: proto) } label: {
                    ProtocolCard(proto: proto, supply: supplyInfo, contents: proto.fullContentsSummary(vials: vials), doseUnit: proto.doseUnit(vials: vials), isBlend: proto.items.contains { item in vials.first(where: { $0.id == item.vialID })?.isBlend == true }, perShot: perShotDetail(proto), loggedToday: proto.loggedToday(in: logs))
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button { editTarget = EditTarget(proto: proto) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button { proto.isActive.toggle() } label: {
                        Label(proto.isActive ? "Pause" : "Resume",
                              systemImage: proto.isActive ? "pause.circle" : "play.circle")
                    }
                    Button(role: .destructive) { context.delete(proto) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .entrance(i)
            }
        }

        if !inactive.isEmpty {
            SectionHeader(title: "Inactive").padding(.top, Space.sm)
            // Paused dimming lives INSIDE ProtocolCard — no call-site opacity here.
            ForEach(Array(inactive.enumerated()), id: \.element.id) { i, proto in
                let supplyInfo = supply(for: proto)
                Button { editTarget = EditTarget(proto: proto) } label: {
                    ProtocolCard(proto: proto, supply: supplyInfo, contents: proto.fullContentsSummary(vials: vials), doseUnit: proto.doseUnit(vials: vials), isBlend: proto.items.contains { item in vials.first(where: { $0.id == item.vialID })?.isBlend == true }, perShot: perShotDetail(proto))
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button { editTarget = EditTarget(proto: proto) } label: {
                        Label("Edit / reactivate", systemImage: "pencil")
                    }
                    Button { proto.isActive.toggle() } label: {
                        Label(proto.isActive ? "Pause" : "Resume",
                              systemImage: proto.isActive ? "pause.circle" : "play.circle")
                    }
                    Button(role: .destructive) { context.delete(proto) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .entrance(active.count + i)
            }
        }
    }

    /// Every compound a protocol delivers per shot, with its dose — blend vials expanded by their
    /// fixed mass ratio, stack items listed in order, each in its own resolved unit. nil for a plain
    /// single-compound protocol (the card's "Dose" stat already covers that).
    private func perShotDetail(_ proto: SavedProtocol) -> String? {
        var parts: [String] = []
        for (i, item) in proto.items.enumerated() {
            let unit = proto.doseUnit(forItemAt: i, vials: vials)
            let dose = i == 0 ? proto.effectiveDose : Mass(micrograms: item.doseMicrograms)
            if let v = vials.first(where: { $0.id == item.vialID }), v.isBlend,
               let p = v.primaryAPI, p.massMicrograms > 0 {
                for api in v.apis {
                    let d = Mass(micrograms: api.massMicrograms / p.massMicrograms * dose.micrograms)
                    parts.append("\(api.name) \(d.displayString(in: unit))")
                }
            } else {
                parts.append("\(item.compoundName) \(dose.displayString(in: unit))")
            }
        }
        return parts.count > 1 ? parts.joined(separator: " · ") : nil
    }

    /// Resolve the vial backing a protocol's primary line into the card's supply readout.
    /// Nil when the protocol isn't linked to a vial — the card then omits its supply row.
    private func supply(for proto: SavedProtocol) -> ProtocolCard.SupplyInfo? {
        guard let vialID = proto.primaryItem?.vialID,
              let vial = vials.first(where: { $0.id == vialID }) else { return nil }
        return ProtocolCard.SupplyInfo(
            fraction: vial.fractionRemaining,
            dosesLeft: max(0, vial.totalDoses - vial.dosesTaken),
            total: vial.totalDoses,
            needsReorder: vial.projection(schedule: proto.schedule).needsReorder
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Stack")
                .font(Typo.screenTitle)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Your protocols and your vials — the plan you track against.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("No protocols yet")
                    .font(Typo.headline)
                    .foregroundStyle(BrandColor.textPrimary)
                Text(vials.isEmpty
                     ? "Protocols are built from your vials — add a vial under Your vials first, then create a protocol from it with a dose and schedule."
                     : "Create one from a vial — pick one of your vials, set the dose per shot, and choose a schedule. You can still log ad-hoc doses without a protocol.")
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
    }
}

import SwiftUI
import SwiftData
import PeptideKit

/// The Stack tab: your vials and your protocols (a "My Vials / My Protocols" segmented
/// control, vials default), plus a link into the compound library under My Vials.
struct ProtocolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
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
                        Text("My Vials").tag(Panel.inventory)
                        Text("My Protocols").tag(Panel.protocols)
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
                    ProtocolCard(proto: proto, supply: supplyInfo, contents: proto.fullContentsSummary(vials: vials))
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
                    ProtocolCard(proto: proto, supply: supplyInfo, contents: proto.fullContentsSummary(vials: vials))
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
                     ? "Protocols are built from your vials — add a vial under My Vials first, then create a protocol from it with a dose and schedule."
                     : "Create one from a vial — pick one of your vials, set the dose per shot, and choose a schedule. You can still log ad-hoc doses without a protocol.")
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
    }
}

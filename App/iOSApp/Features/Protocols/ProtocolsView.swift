import SwiftUI
import SwiftData
import PeptideKit

/// The Protocols tab: your active dosing protocols, plus a link into the compound library.
struct ProtocolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @State private var showBuilder = false
    @State private var editTarget: EditTarget?
    @State private var panel: Panel = .protocols
    @AppStorage("deepLinkInventory") private var deepLinkInventory = false
    private enum Panel: Hashable { case protocols, inventory }
    /// Identifiable wrapper so a tapped protocol can drive `.sheet(item:)` without relying on
    /// the model's own identity semantics.
    private struct EditTarget: Identifiable { let id = UUID(); let proto: SavedProtocol }

    private var active: [SavedProtocol] { protocols.filter(\.isActive) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header

                    Picker("", selection: $panel) {
                        Text("My Protocols").tag(Panel.protocols)
                        Text("My Inventory").tag(Panel.inventory)
                    }
                    .pickerStyle(.segmented)

                    if panel == .protocols {
                        protocolsPanel
                    } else {
                        InventoryList()
                    }

                    DisclaimerBanner(text: "Protocols and inventory are personal records you configure — not medical advice.")
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showBuilder) { ProtocolBuilderView() }
            .sheet(item: $editTarget) { ProtocolBuilderView(editing: $0.proto) }
            // Home's "Add a vial" step deep-links here; jump straight to My Inventory.
            .onAppear { if deepLinkInventory { panel = .inventory; deepLinkInventory = false } }
            .onChange(of: deepLinkInventory) { _, v in if v { panel = .inventory; deepLinkInventory = false } }
        }
    }

    @ViewBuilder private var protocolsPanel: some View {
        PrimaryButton(title: "New protocol", systemImage: "plus") { showBuilder = true }

        if active.isEmpty {
            emptyState
        } else {
            SectionHeader(title: "Active protocols")
            ForEach(active, id: \.id) { proto in
                Button { editTarget = EditTarget(proto: proto) } label: {
                    ProtocolRow(proto: proto)
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button { editTarget = EditTarget(proto: proto) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { context.delete(proto) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }

        NavigationLink { CompoundsView() } label: {
            HStack {
                Image(systemName: "books.vertical.fill").foregroundStyle(BrandColor.accentText)
                Text("Compound library").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
            .padding(Space.lg)
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("What you're running.")
                .font(Typo.screenTitle)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Your protocols and what's on hand — the plan you track against.")
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
                Text("Create one to set a compound, dose, and schedule. You can still log ad-hoc doses without a protocol.")
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
    }
}

struct ProtocolRow: View {
    let proto: SavedProtocol

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(proto.name).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    if proto.isStack { TagChip(text: "Stack", color: BrandColor.accentText) }
                    if proto.isTitrating { TagChip(text: "Ramp-up", color: BrandColor.warning) }
                    Spacer()
                    Text(proto.effectiveDose.displayString).font(Typo.numberMD).foregroundStyle(BrandColor.accentText)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                }
                Text("\(proto.contentsSummary) · \(proto.cadenceText)")
                    .font(.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                if let label = proto.titrationLabel {
                    Text(label).font(.caption2).foregroundStyle(BrandColor.warning)
                }
                if let next = proto.nextDose() {
                    Text("Next: \(next, format: .dateTime.weekday(.abbreviated).month().day())")
                        .font(.caption)
                        .foregroundStyle(BrandColor.success)
                }
            }
        }
    }
}

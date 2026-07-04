import SwiftUI
import SwiftData
import PeptideKit

/// The Protocols tab: your active dosing protocols, plus a link into the compound library.
struct ProtocolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @State private var showBuilder = false

    private var active: [SavedProtocol] { protocols.filter(\.isActive) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header

                    PrimaryButton(title: "New protocol", systemImage: "plus") { showBuilder = true }

                    if active.isEmpty {
                        emptyState
                    } else {
                        SectionHeader(title: "Active protocols")
                        ForEach(active, id: \.id) { proto in
                            ProtocolRow(proto: proto)
                                .contextMenu {
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

                    DisclaimerBanner(text: "Protocols are personal schedules you configure — not medical advice.")
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Protocols")
            .sheet(isPresented: $showBuilder) { ProtocolBuilderView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Your protocols.")
                .font(Typo.displayL)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Compound, dose, and schedule — the plan you track against.")
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
                HStack(alignment: .firstTextBaseline) {
                    Text(proto.name).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Spacer()
                    Text(proto.dose.displayString).font(Typo.numberMD).foregroundStyle(BrandColor.accentText)
                }
                Text("\(proto.compoundName) · \(proto.cadenceText)")
                    .font(.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                if let next = proto.nextDose() {
                    Text("Next: \(next, format: .dateTime.weekday(.abbreviated).month().day())")
                        .font(.caption)
                        .foregroundStyle(BrandColor.success)
                }
            }
        }
    }
}

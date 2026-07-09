import SwiftUI
import SwiftData
import PeptideKit

/// A running record of every dose logged, newest first — reached from the Tools tab. Swipe a
/// row left to delete a mis-logged dose; deleting also gives back the vial draw-down that dose
/// consumed (only for the record that actually decremented — a blend stack is one decrement
/// across several records, so it returns exactly one dose).
struct DoseHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var doses: [LoggedDose]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]

    var body: some View {
        Group {
            if doses.isEmpty {
                ContentUnavailableView("No doses logged yet",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Doses you record in the Log tab show up here."))
            } else {
                List {
                    ForEach(doses) { entry in
                        row(entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: Space.xs, leading: 0, bottom: Space.xs, trailing: 0))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(entry) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .heroScreen()
        .navigationTitle("Dose history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: LoggedDose) -> some View {
        Card(style: .flat) {
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
        .accessibilityElement(children: .combine)
    }

    private func delete(_ entry: LoggedDose) {
        if entry.didDecrement, let vid = entry.vialID,
           let vial = vials.first(where: { $0.id == vid }), vial.dosesTaken > 0 {
            vial.dosesTaken -= 1
        }
        context.delete(entry)
    }
}

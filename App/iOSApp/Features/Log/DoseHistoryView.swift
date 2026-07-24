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
        // Show the dose in its vial's chosen unit when the vial still exists; else fall back.
        let vial = vials.first { $0.id == entry.vialID }
        let unit = vial?.doseUnit ?? MassUnit.auto(forMicrograms: entry.dose.micrograms)
        // A logged blend stores only the primary; reconstruct the full shot from the vial link so
        // the ride-along compounds aren't hidden in history.
        let blend: String? = {
            guard let v = vial, v.isBlend, let primary = v.primaryAPI, primary.massMicrograms > 0 else { return nil }
            return v.apis.map { "\($0.name) \(Mass(micrograms: $0.massMicrograms / primary.massMicrograms * entry.dose.micrograms).displayString(in: unit))" }
                .joined(separator: " · ")
        }()
        return Card(style: .flat) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vial?.isBlend == true ? vial!.apiNames.joined(separator: " + ") : entry.compoundName)
                        .font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text(entry.dose.displayString(in: unit) + (entry.site.map { " · \($0.displayName)" } ?? ""))
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    if let blend {
                        Text("Delivers \(blend)").font(.caption2).foregroundStyle(BrandColor.textSecondary)
                    }
                }
                Spacer()
                Text(entry.timestamp.relativeLabel())
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

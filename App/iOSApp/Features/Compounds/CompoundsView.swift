import SwiftUI
import SwiftData
import PeptideKit

// The compound library (reached from My Vials): the verified catalog with evidence tiers,
// plus the user's own added compounds.

struct CompoundsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomCompound.name) private var custom: [CustomCompound]
    @State private var search = ""
    @State private var showLegend = false
    @State private var showAdd = false

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Alphabetical, filtered by name/alias/category.
    private var results: [Compound] {
        guard !query.isEmpty else { return CompoundCatalog.allSorted }
        return CompoundCatalog.allSorted.filter { c in
            c.name.lowercased().contains(query)
            || c.aliases.contains { $0.lowercased().contains(query) }
            || c.category.rawValue.lowercased().contains(query)
        }
    }

    private var customResults: [CustomCompound] {
        guard !query.isEmpty else { return custom }
        return custom.filter { $0.name.lowercased().contains(query) || $0.categoryRaw.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                searchBar

                if !customResults.isEmpty {
                    SectionHeader(title: "Your compounds")
                    ForEach(customResults, id: \.id) { cc in
                        NavigationLink { CompoundDetailView(compound: cc.asCompound, isCustom: true) } label: {
                            CompoundRow(compound: cc.asCompound, isCustom: true)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) { context.delete(cc); try? context.save() } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    SectionHeader(title: "Library")
                }

                if results.isEmpty && customResults.isEmpty {
                    Card {
                        Text("No compounds match “\(search)”.")
                            .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(results, id: \.id) { compound in
                        NavigationLink { CompoundDetailView(compound: compound) } label: {
                            CompoundRow(compound: compound)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                Button { showAdd = true } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(BrandColor.accentText)
                        Text("Add your own compound").font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(BrandColor.textSecondary)
                    }
                    .padding(Space.lg)
                    .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Compound library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .tint(BrandColor.accentText)
                    .accessibilityLabel("Add your own compound")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLegend = true } label: { Image(systemName: "questionmark.circle") }
                    .tint(BrandColor.accentText)
                    .accessibilityLabel("What the tiers and labels mean")
            }
        }
        .sheet(isPresented: $showLegend) { CompoundLegendView() }
        .sheet(isPresented: $showAdd) { AddCustomCompoundView() }
    }

    private var searchBar: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(BrandColor.textSecondary)
            TextField("Search compounds", text: $search)
                .foregroundStyle(BrandColor.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BrandColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.md - 2)
        .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
    }
}

/// Explains the evidence tiers, the WADA label, and half-life — reachable from the "?" button.
struct CompoundLegendView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Evidence tiers")
                            Text("How much human evidence backs a compound. Higher tiers mean stronger proof it works and is safe in people.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                            tierRow(.fdaApproved, "Approved by the FDA for use in people — the strongest evidence.")
                            tierRow(.humanTrialsUnapproved, "Studied in human trials, but not FDA-approved.")
                            tierRow(.preclinicalOrFailed, "Mostly animal or lab data (or trials that didn't pan out) — little human evidence.")
                            tierRow(.precursorOffLabel, "Evidence is for a topical or precursor form; injected use is off-label and unstudied.")
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionHeader(title: "Labels")
                            HStack(alignment: .top, spacing: Space.md) {
                                TagChip(text: "WADA", color: BrandColor.warning)
                                Text("On the World Anti-Doping Agency prohibited list — banned for drug-tested athletes.")
                                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Half-life (t½)")
                            Text("The time it takes for half of a dose to clear your body. A short t½ (minutes or hours) means it acts and leaves quickly; a long t½ (days) means it lingers and can build up with repeat doses. It's a rough guide to how often something is typically taken — not a dose recommendation.")
                                .font(.caption).foregroundStyle(BrandColor.textSecondary)
                        }
                    }
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("What these mean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func tierRow(_ tier: EvidenceTier, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            EvidenceBadge(tier: tier)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.label).font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textPrimary)
                Text(desc).font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct CompoundRow: View {
    let compound: Compound
    var isCustom: Bool = false

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(compound.name).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xs) {
                    if isCustom {
                        TagChip(text: "Custom", color: BrandColor.accentText)
                    } else {
                        EvidenceBadge(tier: compound.evidenceTier)
                        if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [compound.category.rawValue]
        if let h = compound.halfLifeHours { parts.append(halfLifeShort(h)) }
        return parts.joined(separator: " · ")
    }
    private func halfLifeShort(_ h: Double) -> String {
        if h >= 24 { return "t½ ~\(Int((h / 24).rounded())) d" }
        if h >= 1 { return "t½ ~\(Int(h.rounded())) h" }
        return "t½ <1 h"
    }
}

struct CompoundDetailView: View {
    let compound: Compound
    var isCustom: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(compound.name).font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                    if !compound.aliases.isEmpty {
                        Text(compound.aliases.joined(separator: " · "))
                            .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    }
                    HStack(spacing: Space.sm) {
                        if isCustom {
                            TagChip(text: "Custom", color: BrandColor.accentText)
                        } else {
                            EvidenceBadge(tier: compound.evidenceTier)
                            if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        detailRow("Category", compound.category.rawValue)
                        if isCustom {
                            detailRow("Source", "Added by you")
                        } else {
                            detailRow("Regulatory status", regulatoryLabel)
                            detailRow("Evidence", compound.evidenceTier.label)
                        }
                        if let h = compound.halfLifeHours { detailRow("Half-life", halfLifeLong(h)) }
                        detailRow("Dosed in", compound.preferredDoseUnit.rawValue)
                    }
                }

                if !compound.notes.isEmpty {
                    SectionHeader(title: "Notes")
                    Text(compound.notes).font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }

                if isCustom {
                    DisclaimerBanner(text: Self.customCompoundNote, systemImage: "exclamationmark.triangle")
                }
            }
            .padding(Space.lg)
        }
        .screenBackground()
        .navigationTitle(compound.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The one place a strong warning stays by design: compounds the user added themselves.
    static let customCompoundNote = "You added this compound yourself — PinWise has no verified data on it. Confirm identity, purity, and handling with your supplier's certificate of analysis. PinWise provides no information or assurances for user-added compounds and takes no responsibility for them."

    private var regulatoryLabel: String {
        switch compound.regulatoryStatus {
        case .fdaApproved: return "FDA-approved"
        case .compoundedOnly: return "Compounded only"
        case .researchOnly: return "Research only"
        }
    }
    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(.caption).foregroundStyle(BrandColor.textSecondary)
            Spacer()
            Text(value).font(Typo.body).foregroundStyle(BrandColor.textPrimary).multilineTextAlignment(.trailing)
        }
    }
    private func halfLifeLong(_ h: Double) -> String {
        if h >= 24 { return "~\(Int((h / 24).rounded())) days" }
        if h >= 1 { return "~\(Int(h.rounded())) hours" }
        return "under 1 hour"
    }
}

/// Add a compound of your own — for anything the library doesn't carry. Name first, then
/// just enough structure for the rest of the app (category, dose unit) to work with it.
struct AddCustomCompoundView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [CustomCompound]

    @State private var name = ""
    @State private var category: CompoundCategory = .metabolic
    @State private var doseUnit: MassUnit = .milligram
    @State private var notes = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        CompoundCatalog.all.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            || existing.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
    private var canSave: Bool { !trimmed.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            FieldRow("Compound name") {
                                TextField("e.g. KPV", text: $name).pinwiseField()
                            }
                            if isDuplicate {
                                Text("Already in the library — search for it instead.")
                                    .font(.caption).foregroundStyle(BrandColor.warning)
                            }
                            FieldRow("Category") {
                                Picker("", selection: $category) {
                                    ForEach(CompoundCategory.allCases.filter { $0 != .blend }, id: \.self) {
                                        Text($0.rawValue).tag($0)
                                    }
                                }
                                .pickerStyle(.menu).tint(BrandColor.accentText)
                            }
                            FieldRow("Usually dosed in") {
                                Picker("", selection: $doseUnit) {
                                    ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            FieldRow("Notes", hint: "Optional — source, batch, anything worth remembering.") {
                                TextField("Anything worth remembering", text: $notes, axis: .vertical).pinwiseField()
                            }
                        }
                    }

                    DisclaimerBanner(text: CompoundDetailView.customCompoundNote, systemImage: "exclamationmark.triangle")

                    PrimaryButton(title: "Add compound", systemImage: "checkmark") { save() }
                        .disabled(!canSave).opacity(canSave ? 1 : 0.5)
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Your compound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        guard canSave else { return }
        context.insert(CustomCompound(name: trimmed, categoryRaw: category.rawValue,
                                      doseUnitRaw: doseUnit.rawValue, notes: notes))
        try? context.save()
        dismiss()
    }
}

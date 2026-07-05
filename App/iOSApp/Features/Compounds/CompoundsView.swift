import SwiftUI
import PeptideKit

// The Protocols tab (first real pass): a browsable compound library from the verified
// catalog, with evidence tiers and detail views. Building protocols & inventory from these
// is the next batch.

struct CompoundsView: View {
    @State private var search = ""
    @State private var showLegend = false

    /// Alphabetical, filtered by name/alias/category.
    private var results: [Compound] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return CompoundCatalog.allSorted }
        return CompoundCatalog.allSorted.filter { c in
            c.name.lowercased().contains(q)
            || c.aliases.contains { $0.lowercased().contains(q) }
            || c.category.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                searchBar
                if results.isEmpty {
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
                DisclaimerBanner(
                    text: "Reference information summarized from public research — not medical advice. Evidence tiers reflect how much human data exists."
                )
            }
            .padding(Space.lg)
        }
        .heroScreen()
        .navigationTitle("Compound library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLegend = true } label: { Image(systemName: "questionmark.circle") }
                    .tint(BrandColor.accentText)
                    .accessibilityLabel("What the tiers and labels mean")
            }
        }
        .sheet(isPresented: $showLegend) { CompoundLegendView() }
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

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(compound.name).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xs) {
                    EvidenceBadge(tier: compound.evidenceTier)
                    if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
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
                        EvidenceBadge(tier: compound.evidenceTier)
                        if compound.wadaProhibited { TagChip(text: "WADA", color: BrandColor.warning) }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        detailRow("Category", compound.category.rawValue)
                        detailRow("Regulatory status", regulatoryLabel)
                        detailRow("Evidence", compound.evidenceTier.label)
                        if let h = compound.halfLifeHours { detailRow("Half-life", halfLifeLong(h)) }
                        detailRow("Dosed in", compound.preferredDoseUnit.rawValue)
                    }
                }

                if !compound.notes.isEmpty {
                    SectionHeader(title: "Notes")
                    Text(compound.notes).font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                }

                if compound.requiresResearchDisclaimer {
                    DisclaimerBanner(text: Disclaimer.researchCompound, systemImage: "exclamationmark.triangle")
                }
            }
            .padding(Space.lg)
        }
        .screenBackground()
        .navigationTitle(compound.name)
        .navigationBarTitleDisplayMode(.inline)
    }

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

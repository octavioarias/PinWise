import SwiftUI
import PeptideKit

// The Protocols tab (first real pass): a browsable compound library from the verified
// catalog, with evidence tiers and detail views. Building protocols & inventory from these
// is the next batch.

struct CompoundsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header
                    SectionHeader(title: "Compound library")
                    ForEach(CompoundCatalog.all, id: \.id) { compound in
                        NavigationLink { CompoundDetailView(compound: compound) } label: {
                            CompoundRow(compound: compound)
                        }
                        .buttonStyle(.plain)
                    }
                    DisclaimerBanner(
                        text: "Reference information summarized from public research — not medical advice. Evidence tiers reflect how much human data exists."
                    )
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Protocols")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Your compounds.")
                .font(Typo.displayL)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Browse the library. Building protocols & inventory from these is coming next.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

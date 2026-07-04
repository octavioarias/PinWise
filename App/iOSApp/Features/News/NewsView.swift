import SwiftUI
import PeptideKit

// The News tab — PinWise as the source of truth for peptides & dose tracking.
// Editorial layout (Apple-News style): a large featured story, then a list of the rest.
// Neutral, cited summaries. Reads the bundled sample feed for now; Phase 5c swaps in a
// fetched + cached `feed.json`.

/// Legible tint per category (uses the lighter/brighter hues so text stays readable on dark).
private extension NewsCategory {
    var tint: Color {
        switch self {
        case .safety: return BrandColor.warning
        case .regulatory: return BrandColor.accentText
        case .trialResults, .newCompound: return BrandColor.success
        case .guidance, .general: return BrandColor.textSecondary
        }
    }
}

struct NewsView: View {
    @State private var loader = NewsFeedLoader()
    private var feed: NewsFeed { loader.feed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header

                    if let featured = feed.trending.first {
                        NavigationLink { NewsDetailView(item: featured) } label: {
                            FeaturedNewsCard(item: featured)
                        }
                        .buttonStyle(.plain)
                    }

                    SectionHeader(title: "Latest")
                    ForEach(feed.trending.dropFirst()) { item in
                        NavigationLink { NewsDetailView(item: item) } label: {
                            NewsRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }

                    DisclaimerBanner(
                        text: "PinWise summarizes public research and regulatory updates and links to the original sources. Informational only — not medical advice."
                    )
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("News")
            .task { await loader.load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("The state of peptides,\nin plain language.")
                .font(Typo.displayL)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text("Trials, results, and regulatory news — summarized clearly and linked to the source.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The lead story: a large image banner with the headline overlaid.
struct FeaturedNewsCard: View {
    let item: NewsItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FeedImage(urlString: item.imageURL, tint: item.category.tint)
                .frame(height: 200)
            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    TagChip(text: item.category.rawValue, color: item.category.tint)
                    if item.isMajorUpdate { TagChip(text: "Major", color: BrandColor.accentText) }
                }
                Text(item.headline)
                    .font(Typo.title)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding(Space.lg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(BrandColor.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
}

/// A list row: square thumbnail + headline + meta.
struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Space.md) {
                FeedImage(urlString: item.imageURL, tint: item.category.tint)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        TagChip(text: item.category.rawValue, color: item.category.tint)
                        Spacer()
                        Text(String(item.publishedAt.prefix(10)))
                            .font(.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    Text(item.headline)
                        .font(Typo.headline)
                        .foregroundStyle(BrandColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text("\(item.sources.count) source\(item.sources.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(BrandColor.success)
                }
            }
        }
    }
}

/// Article detail — full summary, compounds, tappable sources, per-item disclaimer.
struct NewsDetailView: View {
    let item: NewsItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                FeedImage(urlString: item.imageURL, tint: item.category.tint)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack {
                        TagChip(text: item.category.rawValue, color: item.category.tint)
                        Spacer()
                        Text(String(item.publishedAt.prefix(10)))
                            .font(.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    Text(item.headline)
                        .font(Typo.title)
                        .foregroundStyle(BrandColor.textPrimary)
                }

                Text(item.summary)
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textPrimary)

                if !item.compounds.isEmpty {
                    SectionHeader(title: "Compounds mentioned")
                    Text(item.compounds.joined(separator: " · "))
                        .font(Typo.body)
                        .foregroundStyle(BrandColor.textSecondary)
                }

                SectionHeader(title: "Sources")
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(item.sources) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                HStack(spacing: Space.sm) {
                                    Image(systemName: "link").foregroundStyle(BrandColor.accentText)
                                    Text(source.name).foregroundStyle(BrandColor.accentText)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                }
                            }
                        }
                    }
                }

                DisclaimerBanner(text: item.disclaimer)
            }
            .padding(Space.lg)
        }
        .screenBackground()
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
    }
}

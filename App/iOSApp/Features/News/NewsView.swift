import SwiftUI
import PeptideKit

// The News tab — PinWise as the hub for sources of truth on peptides and performance medicine.
// Editorial layout (Apple-News style): a masthead, search + category filters, a popular lead
// story, then the latest. Neutral, cited summaries linked to the original sources.

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
    @State private var searchText = ""
    @State private var category: NewsCategory?
    @State private var searchActive = false
    @FocusState private var searchFocused: Bool
    private var feed: NewsFeed { loader.feed }

    private var items: [NewsItem] { feed.trending }
    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty || category != nil }

    /// Featured lead = most popular. "Latest" = everything else, newest first.
    private var featured: NewsItem? { items.first }
    private var latest: [NewsItem] {
        items.filter { $0.id != featured?.id }.sorted { $0.publishedAt > $1.publishedAt }
    }
    private var results: [NewsItem] {
        items.filter { item in
            (category == nil || item.category == category) &&
            (searchText.isEmpty || matches(item, searchText))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    masthead

                    if searchActive {
                        VStack(spacing: Space.lg) {
                            searchBar
                            categoryFilter
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    content

                    DisclaimerBanner(
                        text: "PinWise summarizes public research and regulatory updates and links to the original sources. Informational only — not medical advice."
                    )
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task { await loader.load() }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("News")
                    .font(Typo.displayXL)
                    .foregroundStyle(BrandColor.textPrimary)
                Spacer()
                Button {
                    let willActivate = !searchActive
                    withAnimation(.snappy) {
                        searchActive = willActivate
                        if !willActivate { searchText = ""; category = nil }
                    }
                    searchFocused = willActivate
                } label: {
                    Image(systemName: searchActive ? "xmark" : "magnifyingglass")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(BrandColor.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(BrandColor.surfaceElevated, in: Circle())
                        .overlay(Circle().strokeBorder(BrandColor.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(searchActive ? "Close search" : "Search news")
            }
            Text("Your hub for peptide and performance-medicine research — summarized clearly and linked to the source.")
                .font(Typo.body)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        if isFiltering {
            resultsList
        } else {
            if let featured {
                SectionHeader(title: "Popular")
                newsLink(featured) { FeaturedNewsCard(item: featured) }
            }
            SectionHeader(title: "Latest")
            ForEach(latest) { item in newsLink(item) { NewsRow(item: item) } }
        }
    }

    private var searchBar: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(BrandColor.textSecondary)
            TextField("Search peptides, topics, or sources", text: $searchText)
                .foregroundStyle(BrandColor.textPrimary)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
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

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                filterChip("All", active: category == nil) { category = nil }
                ForEach(NewsCategory.allCases, id: \.self) { c in
                    filterChip(c.rawValue, active: category == c) { category = (category == c ? nil : c) }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private var resultsList: some View {
        HStack {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(BrandColor.textSecondary)
            Spacer()
            Button("Clear filters") { searchText = ""; category = nil }
                .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
        }
        if results.isEmpty {
            Card {
                Text("No stories match. Try a different word or category.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(results) { item in newsLink(item) { NewsRow(item: item) } }
        }
    }

    private func filterChip(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(active ? BrandColor.accent : BrandColor.surfaceElevated, in: Capsule())
                .foregroundStyle(active ? BrandColor.onAccent : BrandColor.textSecondary)
                .overlay(Capsule().strokeBorder(BrandColor.stroke, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func newsLink<Label: View>(_ item: NewsItem, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink { NewsDetailView(item: item) } label: { label() }.buttonStyle(.plain)
    }

    private func matches(_ item: NewsItem, _ query: String) -> Bool {
        let q = query.lowercased()
        return item.headline.lowercased().contains(q)
            || item.summary.lowercased().contains(q)
            || item.category.rawValue.lowercased().contains(q)
            || item.compounds.contains { $0.lowercased().contains(q) }
            || item.sources.contains { $0.name.lowercased().contains(q) }
    }
}

/// The lead story: a prominent, text-forward card (chips → headline → summary → sources).
/// Uses theme tokens so it reads correctly in both light and dark mode.
struct FeaturedNewsCard: View {
    let item: NewsItem

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    TagChip(text: item.category.rawValue, color: item.category.tint)
                    if item.isMajorUpdate { TagChip(text: "Major", color: BrandColor.accentText) }
                    Spacer()
                    Text(String(item.publishedAt.prefix(10)))
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                Text(item.headline)
                    .font(Typo.title)
                    .foregroundStyle(BrandColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.summary)
                    .font(Typo.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(3)
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                    Text("\(item.sources.count) source\(item.sources.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
                }
                .foregroundStyle(BrandColor.success)
            }
        }
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

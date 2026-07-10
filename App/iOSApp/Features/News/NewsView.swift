import SwiftUI
import SwiftData
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

/// Parses a feed item's `publishedAt` (ISO-8601, or a bare `yyyy-MM-dd` fallback) into a Date.
func newsDate(_ iso: String) -> Date? {
    if let d = ISO8601DateFormatter().date(from: iso) { return d }
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "UTC")
    return df.date(from: String(iso.prefix(10)))
}

/// Formats a feed item's `publishedAt` as a friendly abbreviated date (falls back to the raw
/// date substring if parsing ever fails).
func newsDisplayDate(_ iso: String) -> String {
    newsDate(iso).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String(iso.prefix(10))
}

/// True when an article was published within the last `days` — the eligibility window for the
/// "New" tag (keeps old/evergreen items from ever being flagged, and avoids a wall of "New" on
/// first launch). Whether it *actually* shows also depends on the reader's seen state.
func isRecentNews(_ iso: String, within days: Int = 7) -> Bool {
    guard let d = newsDate(iso) else { return false }
    let age = Date().timeIntervalSince(d)
    return age >= 0 && age <= Double(days) * 86_400
}

/// Tracks which News articles the reader has scrolled into view, by first-seen calendar day, so
/// the "New" tag behaves like an unread badge: a recent article stays flagged until it's scrolled
/// past, an article seen today stays flagged for the rest of that day, and it clears the next day.
/// Local-only (UserDefaults), self-pruning past 30 days so it can't grow without bound.
@MainActor @Observable
final class NewsSeenStore {
    private static let key = "newsSeenDays"      // [articleID: "yyyy-MM-dd" first-seen day]
    private var seen: [String: String]

    private static func dayString(_ date: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    init() {
        let raw = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        let cutoff = Self.dayString(Date().addingTimeInterval(-30 * 86_400))
        seen = raw.filter { $0.value >= cutoff }   // lexical == chronological for yyyy-MM-dd
        if seen.count != raw.count { UserDefaults.standard.set(seen, forKey: Self.key) }
    }

    /// Record that an article was scrolled into view (first sighting only).
    func markSeen(_ id: String) {
        guard seen[id] == nil else { return }
        seen[id] = Self.dayString()
        UserDefaults.standard.set(seen, forKey: Self.key)
    }

    /// Still eligible to show "New": never seen, or first seen today (clears the next day).
    func isUnreadToday(_ id: String) -> Bool {
        guard let day = seen[id] else { return true }
        return day == Self.dayString()
    }
}

struct NewsView: View {
    @State private var loader = NewsFeedLoader()
    @State private var seenStore = NewsSeenStore()
    @State private var searchText = ""
    @State private var category: NewsCategory?
    @State private var myStack = false
    @State private var searchActive = false
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var protocols: [SavedProtocol]
    @Query private var vials: [StoredVial]
    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var logs: [LoggedDose]
    private var feed: NewsFeed { loader.feed }

    /// Every compound the user is currently on — from active protocols, inventory, and recent logs.
    private var userCompounds: Set<String> {
        var s = Set<String>()
        for p in protocols where p.isActive { for n in p.compoundNames { s.insert(n.lowercased()) } }
        for v in vials { for n in v.apiNames { s.insert(n.lowercased()) } }
        for l in logs.prefix(80) { s.insert(l.compoundName.lowercased()) }
        return s
    }
    private func matchesStack(_ item: NewsItem) -> Bool {
        guard !userCompounds.isEmpty else { return false }
        // Substring match both ways so catalog aliases line up (e.g. "GHK-Cu" ⟷ "GHK-Cu (injectable)").
        return item.compounds.contains { ic in
            let icl = ic.lowercased()
            return userCompounds.contains { uc in uc == icl || uc.contains(icl) || icl.contains(uc) }
        }
    }

    private var items: [NewsItem] { feed.trending }
    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || category != nil || myStack
    }

    /// Featured lead — personalized. If the user is on compounds and any story mentions one of
    /// them, the highest-ranked matching story leads; otherwise the top editorial story. New
    /// users (empty stack) always see the editorial Top story.
    private var featured: NewsItem? {
        if !userCompounds.isEmpty, let mine = items.first(where: { matchesStack($0) }) { return mine }
        return items.first
    }
    /// True when the lead was chosen because it matches the user's stack (drives the header copy).
    private var featuredIsPersonalized: Bool {
        guard let featured, !userCompounds.isEmpty else { return false }
        return matchesStack(featured)
    }
    /// "Latest" = everything else, newest first.
    private var latest: [NewsItem] {
        items.filter { $0.id != featured?.id }.sorted { $0.publishedAt > $1.publishedAt }
    }
    private var results: [NewsItem] {
        items.filter { item in
            (category == nil || item.category == category) &&
            (searchText.isEmpty || matches(item, searchText)) &&
            (!myStack || matchesStack(item))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    masthead

                    stackToggle

                    if searchActive {
                        VStack(spacing: Space.lg) {
                            searchBar
                            categoryFilter
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    content
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task { await loader.load() }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center) {
                Text("News")
                    .font(Typo.screenTitle)
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

    private var stackToggle: some View {
        HStack(spacing: Space.sm) {
            SelectableChip(title: "My compounds", isSelected: myStack) {
                withAnimation(.snappy) { myStack.toggle() }
            }
            if myStack {
                Text(userCompounds.isEmpty ? "Add a protocol or log a dose to use this"
                                           : "Filtered to what you're taking")
                    .font(.caption2).foregroundStyle(BrandColor.textSecondary)
            }
            Spacer()
        }
        .sensoryFeedback(.selection, trigger: myStack)
    }

    @ViewBuilder private var content: some View {
        if isFiltering {
            resultsList
        } else {
            if let featured {
                SectionHeader(title: featuredIsPersonalized ? "Top story for you" : "Top story")
                newsLink(featured) { FeaturedNewsCard(item: featured, seenStore: seenStore) }
            }
            SectionHeader(title: "Latest")
            ForEach(latest) { item in rowLink(item) }
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
                SelectableChip(title: "All", isSelected: category == nil) { category = nil }
                ForEach(NewsCategory.allCases, id: \.self) { c in
                    SelectableChip(title: c.rawValue, isSelected: category == c) {
                        category = (category == c ? nil : c)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .sensoryFeedback(.selection, trigger: category)
    }

    @ViewBuilder private var resultsList: some View {
        HStack {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(BrandColor.textSecondary)
            Spacer()
            Button("Clear filters") { searchText = ""; category = nil; myStack = false }
                .font(.caption.weight(.semibold)).foregroundStyle(BrandColor.accentText)
        }
        if results.isEmpty {
            Card {
                Text(myStack && userCompounds.isEmpty
                     ? "Add a protocol or log a dose — then this shows news about the compounds you're taking."
                     : "No stories match. Try a different word or category.")
                    .font(Typo.body).foregroundStyle(BrandColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(results) { item in rowLink(item) }
        }
    }

    private func newsLink<Label: View>(_ item: NewsItem, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink { NewsDetailView(item: item) } label: { label() }.buttonStyle(PressableStyle())
    }

    /// A list-row link with the shared scroll-edge treatment (rows only — the featured card
    /// stays static). Scale is ternaried out under Reduce Motion; the fade stays.
    private func rowLink(_ item: NewsItem) -> some View {
        newsLink(item) { NewsRow(item: item, seenStore: seenStore) }
            .scrollTransition(axis: .vertical) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.8)
                    .scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.98))
            }
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

/// A small "New" tag (red dot + label) flagging a recently-published article.
private struct NewBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(BrandColor.danger).frame(width: 6, height: 6)
            Text("New")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BrandColor.danger)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New")
    }
}

/// The lead story: a prominent, text-forward card (chips → headline → summary → sources).
/// Uses theme tokens so it reads correctly in both light and dark mode.
struct FeaturedNewsCard: View {
    let item: NewsItem
    var seenStore: NewsSeenStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    TagChip(text: item.category.rawValue, color: item.category.tint)
                    if item.isMajorUpdate { TagChip(text: "Major", color: BrandColor.accentText) }
                    Spacer()
                    if isRecentNews(item.publishedAt) && seenStore.isUnreadToday(item.id) { NewBadge() }
                    Text(newsDisplayDate(item.publishedAt))
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                Text(item.headline)
                    .font(Typo.title)
                    .foregroundStyle(BrandColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.listText)
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
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            if visible, isRecentNews(item.publishedAt) { seenStore.markSeen(item.id) }
        }
    }
}

/// A list row: square thumbnail + headline + meta.
struct NewsRow: View {
    let item: NewsItem
    var seenStore: NewsSeenStore

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Space.md) {
                FeedImage(urlString: item.imageURL, tint: item.category.tint)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        TagChip(text: item.category.rawValue, color: item.category.tint)
                        Spacer()
                        if isRecentNews(item.publishedAt) && seenStore.isUnreadToday(item.id) { NewBadge() }
                        Text(newsDisplayDate(item.publishedAt))
                            .font(.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    Text(item.headline)
                        .font(Typo.headline)
                        .foregroundStyle(BrandColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(item.listText)
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .lineLimit(2)
                    Text("\(item.sources.count) source\(item.sources.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(BrandColor.success)
                }
            }
        }
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            if visible, isRecentNews(item.publishedAt) { seenStore.markSeen(item.id) }
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
                    // The one sanctioned on-image badge — frosted, over real photo pixels.
                    .overlay(alignment: .topLeading) {
                        FrostedTagChip(text: item.category.rawValue)
                            .padding(Space.md)
                    }

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(newsDisplayDate(item.publishedAt))
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
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

                if !item.disclaimer.isEmpty {
                    Text(item.disclaimer)
                        .font(.caption2)
                        .foregroundStyle(BrandColor.textSecondary)
                }
            }
            .padding(Space.lg)
        }
        .screenBackground()
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
    }
}

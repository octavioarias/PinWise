import Foundation
import PeptideKit

/// Loads the News feed: bundled sample → on-disk cache → live fetch (when a feed URL is
/// configured). Always has content to show; the network is best-effort.
@MainActor
@Observable
final class NewsFeedLoader {
    private(set) var feed: NewsFeed
    /// True while the first live fetch is in flight — lets the UI show a loading state instead of a
    /// bare header on a cold start when there's no cache/sample content yet.
    private(set) var isLoading = false
    private let url: URL?

    private static var cacheURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("news-feed.json")
    }

    init(url: URL? = AppConfig.newsFeedURL) {
        self.url = url
        self.feed = Self.loadCache()
            ?? (try? NewsFeed.decodeSample())
            ?? NewsFeed(version: 0, generatedAt: "", items: [])
    }

    /// Fetches the live feed if a URL is configured; otherwise keeps the sample/cache.
    func load() async {
        guard let url else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(NewsFeed.self, from: data)
            feed = decoded
            if let cache = Self.cacheURL { try? data.write(to: cache) }
        } catch {
            // Keep whatever we already have (cache or bundled sample).
        }
    }

    private static func loadCache() -> NewsFeed? {
        guard let cache = cacheURL, let data = try? Data(contentsOf: cache) else { return nil }
        return try? JSONDecoder().decode(NewsFeed.self, from: data)
    }
}

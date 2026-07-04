import Foundation

/// App-wide configuration constants.
enum AppConfig {
    /// URL of the published `feed.json` for live News. `nil` = use the bundled sample feed.
    /// Set this once the feed is hosted publicly (e.g. GitHub Pages / Cloudflare Pages) — the
    /// pipeline in `scripts/build-feed.mjs` + `.github/workflows/news-feed.yml` generates it.
    static let newsFeedURL: URL? = nil
}

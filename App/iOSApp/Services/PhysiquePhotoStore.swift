import UIKit

/// On-device store for physique / progress photos. Each photo is a JPEG in a dedicated folder
/// under Application Support — like `ProfilePhotoStore`, it is strictly local and never uploaded
/// or synced. SwiftData holds only the filename (`PhysiquePhoto`); the pixels live here.
enum PhysiquePhotoStore {
    /// Longest edge a stored photo is downscaled to — bounds disk use while keeping enough
    /// detail to compare physique over time. Aspect ratio is preserved (no square crop).
    private static let maxEdge: CGFloat = 1280

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PhysiquePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Persist an image, returning the generated filename to store on the `PhysiquePhoto`
    /// (nil if encoding/writing failed). Downscaled and re-encoded as JPEG.
    static func save(_ image: UIImage) -> String? {
        let scaled = downscale(image, maxEdge: maxEdge)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func image(named filename: String) -> UIImage? {
        guard !filename.isEmpty else { return nil }
        return UIImage(contentsOfFile: url(for: filename).path)
    }

    static func delete(named filename: String) {
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    /// Aspect-preserving downscale so the longest edge is at most `maxEdge` (no upscaling).
    private static func downscale(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}

import Foundation
import UIKit

/// In-memory cache for remote restaurant images (URLs are stable; avoids re-fetch on tab switches).
enum RestaurantImageMemoryCache {
    static let shared: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 500
        c.totalCostLimit = 120 * 1024 * 1024
        return c
    }()

    static func image(for url: URL) -> UIImage? {
        shared.object(forKey: url.absoluteString as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        shared.setObject(image, forKey: url.absoluteString as NSString)
    }
}

/// Dedupes in-flight downloads and fills `RestaurantImageMemoryCache`.
actor RestaurantImageLoader {
    static let shared = RestaurantImageLoader()

    private var inflight: [String: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let hit = RestaurantImageMemoryCache.image(for: url) {
            return hit
        }
        if let existing = inflight[key] {
            return await existing.value
        }
        let task = Task<UIImage?, Never> {
            await Self.downloadAndDecode(url: url, key: key)
        }
        inflight[key] = task
        let result = await task.value
        inflight.removeValue(forKey: key)
        return result
    }

    private static func downloadAndDecode(url: URL, key: String) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty else { return nil }
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            if let decoded {
                RestaurantImageMemoryCache.store(decoded, for: url)
            }
            return decoded
        } catch {
            return nil
        }
    }
}

enum RestaurantImageCacheBootstrap {
    /// Larger HTTP cache so cold starts can still hit disk after process launch.
    static func configureURLCache() {
        let memory = 64 * 1024 * 1024
        let disk = 256 * 1024 * 1024
        let diskURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DropFeedURLCache", isDirectory: true)
        if let diskURL, !FileManager.default.fileExists(atPath: diskURL.path) {
            try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
        }
        if let diskURL {
            URLCache.shared = URLCache(
                memoryCapacity: memory,
                diskCapacity: disk,
                directory: diskURL
            )
        } else {
            URLCache.shared = URLCache(
                memoryCapacity: memory,
                diskCapacity: disk,
                diskPath: "dropfeed_images"
            )
        }
    }
}

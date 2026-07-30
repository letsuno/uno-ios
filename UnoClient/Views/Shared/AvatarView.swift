import ImageIO
import SwiftUI
import UIKit

/// Remote avatar with an initials fallback. `url` should already be resolved
/// against the server base via `ServerEndpoint.resolveAvatar`. Images are
/// downsampled to the render size and cached, so the many seat/scoreboard
/// rebuilds during a game don't re-fetch or re-decode full-resolution art.
struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackColor.gradient)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            image = nil
            guard let url else { return }
            // Downsample generously above the point size to stay crisp on @3x.
            image = await AvatarImageCache.shared.image(url, pixelSize: size * 3)
        }
    }

    private var initials: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased()
    }

    private var fallbackColor: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

/// Downsampling image cache keyed by URL + target pixel size. An actor keeps the
/// `NSCache` and fetch path race-free; `UIImage` is Sendable so results cross back cleanly.
actor AvatarImageCache {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSString, UIImage>()

    func image(_ url: URL, pixelSize: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)@\(Int(pixelSize))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
            let downsampled = Self.downsample(data, to: pixelSize)
        else { return nil }
        cache.setObject(downsampled, forKey: key)
        return downsampled
    }

    private static func downsample(_ data: Data, to pixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, pixelSize),
            ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
}

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

    private var initials: String { AvatarPalette.initials(name) }

    private var fallbackColor: Color { AvatarPalette.color(for: name) }
}

/// Stand-in identity for a player with no avatar image. Shared so the circular avatar
/// and the seat backdrop agree on the same colour for the same person.
enum AvatarPalette {
    private static let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint]

    static func color(for name: String) -> Color {
        colors[abs(name.hashValue) % colors.count]
    }

    static func initials(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased()
    }
}

/// The avatar as a card's backdrop rather than a badge: blurred to stay behind the text
/// and faded from the top-left corner to the bottom-right so the label side of the card
/// keeps enough contrast for names and status chips.
struct AvatarBackdrop: View {
    let url: URL?
    let name: String

    @State private var image: UIImage?

    var body: some View {
        // `Color.clear` takes the host cell's size; a bare `scaledToFill` image inside a
        // `.background` would size the container to the image and spill past the card.
        Color.clear
            .overlay {
                ZStack {
                    artwork
                    // Second copy, blurred, revealed from the top-left corner onward:
                    // the picture reads sharp where it starts and dissolves into the
                    // card where the name and chips sit.
                    artwork
                        .blur(radius: 14)
                        .mask(diagonal(from: .clear, to: .white))
                }
            }
            .clipped()
            .mask(
                diagonal(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.5), location: 0.5),
                        .init(color: .clear, location: 1),
                    ]
                )
            )
            .allowsHitTesting(false)
            .task(id: url) {
                image = nil
                guard let url else { return }
                // A seat card is ~360pt wide at @3x. Decoding smaller and letting
                // `scaledToFill` stretch it produced visible blocky steps.
                image = await AvatarImageCache.shared.image(url, pixelSize: 560)
            }
    }

    /// No initials here: the nickname sits right on top of this, and a giant repeat of
    /// its first two letters is noise. A player without a picture just gets their colour.
    @ViewBuilder
    private var artwork: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(AvatarPalette.color(for: name).gradient)
                .opacity(0.4)
        }
    }

    private func diagonal(from start: Color, to end: Color) -> LinearGradient {
        diagonal(stops: [.init(color: start, location: 0), .init(color: end, location: 1)])
    }

    private func diagonal(stops: [Gradient.Stop]) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
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

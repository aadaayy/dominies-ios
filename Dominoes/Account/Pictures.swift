import SwiftUI
import UIKit

/// Turning a photo from the library into a profile picture: upright, cropped
/// to the square the player framed, shrunk to 512 by 512 and saved as a small
/// JPEG (about 50 KB), so it uploads quickly and costs little storage.
enum Pictures {
    /// Largest side a photo is kept at while the player frames it. Plenty for
    /// a 512 pixel picture after zooming in, and light on memory.
    static let workingSize: CGFloat = 2048

    /// The photo upright (phones save many photos turned, with a note to turn
    /// them back) and no bigger than `workingSize`.
    static func prepare(_ image: UIImage) -> UIImage {
        let size = image.size
        let scale = min(1, workingSize / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// The square `crop` (in the photo's pixels) as a finished picture.
    static func picture(from image: UIImage, crop: CGRect) -> UIImage {
        let side = CGFloat(Player.pictureSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let k = side / max(crop.width, 1)
            image.draw(in: CGRect(x: -crop.minX * k, y: -crop.minY * k,
                                  width: image.size.width * k, height: image.size.height * k))
        }
    }

    /// The picture as JPEG, comfortably under the bucket's 1 MB limit.
    static func jpeg(_ picture: UIImage) -> Data? {
        for quality in [0.82, 0.7, 0.55] {
            if let data = picture.jpegData(compressionQuality: quality), data.count < 900_000 { return data }
        }
        return nil
    }
}

/// Pictures already on this phone, by address, so a new picture shows at
/// once instead of loading again, and the checks' pretend pictures show
/// without a network.
@MainActor
enum AvatarCache {
    private static var images: [URL: UIImage] = [:]

    static func image(for url: URL) -> UIImage? { images[url] }

    static func store(_ image: UIImage, for url: URL) {
        images[url] = image
    }
}

#if DEBUG
/// Pictures drawn on the phone for the automatic checks, which have no photo
/// library or Google account.
@MainActor
enum MockPictures {
    /// Alex's "Google photo".
    static let googleURL = URL(string: "https://mock.dominoes.invalid/alex-google.jpg")!

    /// A soft portrait-like picture: a warm disc on teal.
    static var google: UIImage {
        let side: CGFloat = 256
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.10, green: 0.45, blue: 0.50, alpha: 1).cgColor,
                          UIColor(red: 0.05, green: 0.25, blue: 0.35, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            UIColor(red: 0.96, green: 0.80, blue: 0.62, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: side * 0.32, y: side * 0.18, width: side * 0.36, height: side * 0.40))
            UIColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: side * 0.14, y: side * 0.62, width: side * 0.72, height: side * 0.60))
        }
    }

    /// A wide "photo" from the library: sky, sun and hills, to frame.
    static var libraryPhoto: UIImage {
        let size = CGSize(width: 1600, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let sky = [UIColor(red: 0.98, green: 0.62, blue: 0.40, alpha: 1).cgColor,
                       UIColor(red: 0.45, green: 0.30, blue: 0.65, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: nil) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            }
            UIColor(red: 1, green: 0.88, blue: 0.55, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 640, y: 380, width: 320, height: 320))
            UIColor(red: 0.18, green: 0.32, blue: 0.30, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: -300, y: 760, width: 1300, height: 900))
            UIColor(red: 0.12, green: 0.24, blue: 0.24, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 700, y: 820, width: 1300, height: 900))
        }
    }
}
#endif

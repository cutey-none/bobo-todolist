import AppKit
import ImageIO

enum ImageAttachment {
    static func normalizedData(from url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return normalizedData(from: image)
    }

    static func normalizedData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return normalizedData(from: cgImage)
    }

    static func image(from data: Data) -> NSImage? { NSImage(data: data) }

    private static func normalizedData(from image: CGImage) -> Data? {
        let alpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let scale = min(1, 1600 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(using: alpha ? .png : .jpeg,
                                                               properties: [.compressionFactor: 0.85])
    }
}

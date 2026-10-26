import CoreGraphics
import Foundation
import ImageIO
import SnagKit
import Vision

/// On-device image understanding. Photos never leave the phone here.
nonisolated enum VisionService {
    /// Scene/object labels for a photo, e.g. ("dog", 0.92), ("mountain", 0.71).
    static func labels(for image: CGImage, minimumConfidence: Float = 0.2, limit: Int = 12) async -> [(text: String, confidence: Double)] {
        let request = ClassifyImageRequest()
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { (text: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: Double($0.confidence)) }
    }

    /// Lines of text in an image, top to bottom.
    static func text(in image: CGImage, fast: Bool = false) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// Interests suggested by a batch of photos (e.g. Instagram screenshots).
    /// Labels from every photo are pooled, so one beach photo doesn't make
    /// someone a "beach person" but ten do.
    static func interests(from images: [CGImage]) async -> (interests: [WeightedInterest], signals: [String]) {
        var pooled: [String: Double] = [:]
        var texts: [String] = []
        for image in images {
            for label in await labels(for: image) {
                pooled[label.text, default: 0] += label.confidence
            }
            // Screenshots carry captions and handles; they're great signals.
            texts += await text(in: image, fast: true).filter { $0.count >= 4 && $0.count <= 60 }
        }
        let count = Double(max(images.count, 1))
        let labelSignals = pooled.map { (text: $0.key, confidence: min(1, $0.value / count * 1.6)) }
        let textSignals = texts.map { (text: $0, confidence: 0.3) }
        let interests = InterestMatcher.interests(from: labelSignals + textSignals, source: .photos)
        let topLabels = pooled.sorted { $0.value > $1.value }.prefix(20).map(\.key)
        return (interests, topLabels)
    }
}

extension CGImage {
    /// Downscaled copy for faster analysis.
    nonisolated func downscaled(maxDimension: CGFloat = 1024) -> CGImage {
        let w = CGFloat(width), h = CGFloat(height)
        let scale = min(1, maxDimension / max(w, h))
        guard scale < 1,
              let context = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return self }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: w * scale, height: h * scale))
        return context.makeImage() ?? self
    }
}

nonisolated enum ImageLoading {
    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

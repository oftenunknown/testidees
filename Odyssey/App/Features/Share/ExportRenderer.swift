import AVFoundation
import CoreVideo
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import OdysseyKit

enum ExportError: LocalizedError {
    case renderFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed: "Couldn't draw the image."
        case .writeFailed(let what): "Couldn't save the \(what)."
        }
    }
}

/// Renders the export views to PNG, GIF and MP4 files in the temporary folder.
enum ExportRenderer {
    /// Pages that make a good short animation.
    static func animatedPages(for recap: Recap, showNames: Bool, showRoutes: Bool) -> [StoryPage] {
        let all = StoryScript.pages(for: recap)
        let wanted: [StoryPage] = [.intro, .totals, .journey, .climb, .moments, .crew, .routes, .persona, .outro]
        return wanted.filter { page in
            guard all.contains(page) else { return false }
            if page == .crew, !showNames { return false }
            if page == .routes, !showRoutes { return false }
            return true
        }
    }

    static func image<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    static func fileURL(_ name: String, _ ext: String) -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OdysseyExports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).\(ext)")
        try? FileManager.default.removeItem(at: url)
        return url
    }

    static func writePNG(_ image: CGImage, name: String) throws -> URL {
        let url = fileURL(name, "png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.writeFailed("image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed("image") }
        return url
    }

    // MARK: - Still images

    static func storyCard(recap: Recap, env: StoryEnvironment, theme: PageTheme, name: String) throws -> URL {
        guard let image = image(StoryCardPoster(recap: recap, env: env, theme: theme), scale: 1080 / ExportLayout.page.width) else {
            throw ExportError.renderFailed
        }
        return try writePNG(image, name: name)
    }

    static func longImage(recap: Recap, env: StoryEnvironment, theme: PageTheme, name: String) throws -> URL {
        let poster = LongPoster(recap: recap, env: env, theme: theme)
        // Measure first so very long posters stay under the GPU's texture limit.
        let measured = ImageRenderer(content: poster)
        measured.scale = 1
        let height = measured.uiImage?.size.height ?? 4000
        let scale = min(1080 / ExportLayout.longWidth, 15_500 / max(height, 1))
        guard let image = image(poster, scale: scale) else { throw ExportError.renderFailed }
        return try writePNG(image, name: name)
    }

    static func pageImages(recap: Recap, env: StoryEnvironment, name: String) throws -> [URL] {
        try StoryScript.pages(for: recap).enumerated().compactMap { i, page in
            if page == .crew, !env.showNames { return nil }
            if page == .routes, !env.showRoutes { return nil }
            guard let image = image(ExportPage(page: page, env: env, progress: 1), scale: 1080 / ExportLayout.page.width) else { return nil }
            return try writePNG(image, name: "\(name)-\(String(format: "%02d", i + 1))-\(page.rawValue)")
        }
    }

    // MARK: - GIF

    /// An endlessly looping GIF: each page animates in, then holds.
    static func gif(recap: Recap, env: StoryEnvironment, name: String, width: CGFloat, fps: Double = 10,
                    progress: (Double) -> Void) async throws -> URL {
        let pages = animatedPages(for: recap, showNames: env.showNames, showRoutes: env.showRoutes)
        let animatedFrames = Int(2.2 * fps)
        let total = pages.count * (animatedFrames + 1)
        let url = fileURL(name, "gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, total, nil) else {
            throw ExportError.writeFailed("GIF")
        }
        let loop = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, loop as CFDictionary)
        let scale = width / ExportLayout.page.width
        var done = 0
        for page in pages {
            for frame in 0...animatedFrames {
                try Task.checkCancellation()
                let t = Double(frame) / Double(animatedFrames)
                // ImageIO expects exactly `total` frames, so a missing one is an error.
                guard let image = image(ExportPage(page: page, env: env, progress: t), scale: scale) else { throw ExportError.renderFailed }
                let delay = frame == animatedFrames ? 1.6 : 1 / fps
                let properties = [kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay,
                    kCGImagePropertyGIFUnclampedDelayTime as String: delay,
                ]]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                done += 1
                progress(Double(done) / Double(total))
                await Task.yield()
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed("GIF") }
        return url
    }

    // MARK: - Video

    /// 1080 × 1920 H.264, the format Instagram and TikTok stories expect.
    static func video(recap: Recap, env: StoryEnvironment, name: String, fps: Int32 = 30,
                      progress: (Double) -> Void) async throws -> URL {
        let pages = animatedPages(for: recap, showNames: env.showNames, showRoutes: env.showRoutes)
        let width = 1080, height = 1920
        let url = fileURL(name, "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw ExportError.writeFailed("video") }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.writeFailed("video") }
        writer.startSession(atSourceTime: .zero)

        let animated = Int(2.2 * Double(fps)), hold = Int(1.4 * Double(fps))
        let total = pages.count * (animated + hold)
        let scale = CGFloat(width) / ExportLayout.page.width
        var frameIndex: Int64 = 0

        func append(_ buffer: CVPixelBuffer) async throws {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(8))
            }
            if !adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps)) {
                throw ExportError.writeFailed("video")
            }
            frameIndex += 1
            progress(Double(frameIndex) / Double(total))
        }

        for page in pages {
            var last: CVPixelBuffer?
            for frame in 0..<animated {
                try Task.checkCancellation()
                let t = Double(frame) / Double(animated - 1)
                guard let image = image(ExportPage(page: page, env: env, progress: t), scale: scale),
                      let buffer = pixelBuffer(from: image, width: width, height: height, pool: adaptor.pixelBufferPool) else { continue }
                try await append(buffer)
                last = buffer
            }
            if let last {
                for _ in 0..<hold { try await append(last) }
            }
            await Task.yield()
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw ExportError.writeFailed("video") }
        return url
    }

    static func pixelBuffer(from image: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        } else {
            let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

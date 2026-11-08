import AVKit
import ImageIO
import SwiftUI
import UIKit
import OdysseyKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case card, long, pages, gif, video
    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: "Card"
        case .long: "Long"
        case .pages: "Pages"
        case .gif: "GIF"
        case .video: "Video"
        }
    }

    var detail: String {
        switch self {
        case .card: "One 1080 × 1920 summary card, story-sized."
        case .long: "Everything in one tall image."
        case .pages: "Every story page as its own image."
        case .gif: "The story, animated and looping."
        case .video: "1080 × 1920 video for Instagram and TikTok stories."
        }
    }

    var symbol: String {
        switch self {
        case .card: "rectangle.portrait.fill"
        case .long: "rectangle.split.1x2.fill"
        case .pages: "square.stack.fill"
        case .gif: "photo.stack.fill"
        case .video: "film.fill"
        }
    }
}

/// Make something to post: pick a format and theme, preview, then share or save.
struct ShareStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var initialPage: StoryPage?

    @State private var format: ExportFormat = .card
    @State private var preview: UIImage?
    @State private var outputs: [URL] = []
    @State private var isWorking = false
    @State private var progress = 0.0
    @State private var error: String?
    @State private var gifSize: GIFSize = .small
    @State private var job: Task<Void, Never>?

    enum GIFSize: String, CaseIterable, Identifiable {
        case small, large
        var id: String { rawValue }
        var width: CGFloat { self == .small ? 432 : 540 }
        var title: String { self == .small ? "432 × 768" : "540 × 960" }
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    previewArea
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { f in
                            Label(f.title, systemImage: f.symbol).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("export-format")
                    Text(format.detail).font(.footnote).foregroundStyle(.secondary)

                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Theme", selection: $settings.shareTheme) {
                                ForEach(ShareTheme.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .disabled(format != .card && format != .long)
                            Toggle("Show companion names", isOn: $settings.shareCompanionNames)
                            Toggle("Show route art", isOn: $settings.shareRouteArt)
                            if format == .gif {
                                Picker("GIF size", selection: $gifSize) {
                                    ForEach(GIFSize.allCases) { Text($0.title).tag($0) }
                                }
                            }
                        }
                    }

                    actions
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { job?.cancel(); dismiss() }
                }
            }
            .task(id: PreviewKey(format: format, theme: settings.shareTheme, names: settings.shareCompanionNames, routes: settings.shareRouteArt)) {
                outputs = []
                error = nil
                renderPreview()
            }
            .onDisappear { job?.cancel() }
        }
    }

    private struct PreviewKey: Hashable {
        var format: ExportFormat
        var theme: ShareTheme
        var names: Bool
        var routes: Bool
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        Group {
            if format == .gif, let url = outputs.first {
                AnimatedImageView(url: url)
                    .aspectRatio(9 / 16, contentMode: .fit)
            } else if format == .video, let url = outputs.first {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(9 / 16, contentMode: .fit)
            } else if let preview {
                if format == .long {
                    ScrollView {
                        Image(uiImage: preview).resizable().scaledToFit()
                    }
                } else {
                    Image(uiImage: preview).resizable().scaledToFit()
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxHeight: 520)
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .accessibilityIdentifier("export-preview")
    }

    private var env: StoryEnvironment? {
        guard let recap = model.recap else { return nil }
        return StoryEnvironment(
            recap: recap, units: model.units, narrator: model.narrator, firstWeekday: settings.firstWeekday,
            showNames: settings.shareCompanionNames, showRoutes: settings.shareRouteArt, isExport: true
        )
    }

    private var theme: PageTheme { PageTheme.share(settings.shareTheme) }

    private func renderPreview() {
        guard let env else { return }
        let view: AnyView
        switch format {
        case .card:
            view = AnyView(StoryCardPoster(recap: env.recap, env: env, theme: theme))
        case .long:
            view = AnyView(LongPoster(recap: env.recap, env: env, theme: theme))
        case .pages, .gif, .video:
            let pages = StoryScript.pages(for: env.recap)
            let page = initialPage.flatMap { pages.contains($0) ? $0 : nil } ?? (pages.contains(.journey) ? .journey : .intro)
            view = AnyView(ExportPage(page: page, env: env, progress: 1))
        }
        preview = ExportRenderer.image(view, scale: 1.2).map { UIImage(cgImage: $0) }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if isWorking {
                ProgressView(value: progress) {
                    Text(format == .video ? "Rendering video…" : format == .gif ? "Animating GIF…" : "Rendering…")
                }
                Button("Cancel", role: .cancel) { job?.cancel() }
            } else if !outputs.isEmpty {
                if outputs.count == 1, let url = outputs.first {
                    ShareLink(item: url, preview: SharePreview(shareTitle, image: Image(uiImage: preview ?? UIImage()))) {
                        Label("Share or save", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("export-share")
                } else {
                    ShareLink(items: outputs) {
                        Label("Share or save \(outputs.count) images", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("export-share")
                }
                Text("Tip: choose “Save Image” or “Save Video” in the share sheet to add it to Photos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    create()
                } label: {
                    Label("Create \(format.title.lowercased())", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(model.recap == nil)
                .accessibilityIdentifier("export-create")
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Palette.coral)
            }
        }
    }

    private var shareTitle: String {
        "My \(model.range.title(format: model.narrator.format)) Odyssey"
    }

    private var fileName: String {
        let title = model.range.title(format: DayFormat(locale: Locale(identifier: "en_US_POSIX")))
        let safe = title.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "Odyssey-\(String(safe))"
    }

    private func create() {
        guard let env else { return }
        isWorking = true
        progress = 0
        error = nil
        let format = format, theme = theme, name = fileName, gifWidth = gifSize.width
        job = Task {
            defer { isWorking = false }
            do {
                switch format {
                case .card:
                    outputs = [try ExportRenderer.storyCard(recap: env.recap, env: env, theme: theme, name: name)]
                case .long:
                    outputs = [try ExportRenderer.longImage(recap: env.recap, env: env, theme: theme, name: "\(name)-long")]
                case .pages:
                    outputs = try ExportRenderer.pageImages(recap: env.recap, env: env, name: name)
                case .gif:
                    outputs = [try await ExportRenderer.gif(recap: env.recap, env: env, name: name, width: gifWidth) { progress = $0 }]
                case .video:
                    outputs = [try await ExportRenderer.video(recap: env.recap, env: env, name: name) { progress = $0 }]
                }
                model.showToast(format == .pages ? "\(outputs.count) images ready" : "Ready to share")
            } catch is CancellationError {
                outputs = []
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Plays a GIF file (SwiftUI's Image shows only the first frame).
struct AnimatedImageView: UIViewRepresentable {
    var url: URL

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = Self.animatedImage(url)
        view.startAnimating()
    }

    static func animatedImage(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var duration = 0.0
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // UIImage animations use one duration; repeat long frames to keep the rhythm.
            let repeats = max(1, Int((delay / 0.1).rounded()))
            for _ in 0..<repeats { frames.append(UIImage(cgImage: image)) }
            duration += delay
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

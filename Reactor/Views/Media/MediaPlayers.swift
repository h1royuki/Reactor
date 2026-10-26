import SwiftUI
import UIKit
import ImageIO
import WebKit

// MARK: - Animated GIF

final class GIFImageView: UIImageView {
    private final class StopToken { var stopped = false }
    private var token: StopToken?
    private var currentURL: URL?

    func play(data: Data, url: URL) {
        guard url != currentURL else { return }
        stop()
        currentURL = url
        let token = StopToken()
        self.token = token
        _ = CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, cgImage, stop in
            guard let self, !token.stopped else {
                stop.pointee = true
                return
            }
            self.image = UIImage(cgImage: cgImage)
        }
    }

    func stop() {
        token?.stopped = true
        token = nil
        currentURL = nil
    }
}

struct AnimatedImage: UIViewRepresentable {
    let data: Data
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> GIFImageView {
        let view = GIFImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: GIFImageView, context: Context) {
        view.contentMode = contentMode
        view.play(data: data, url: url)
    }

    static func dismantleUIView(_ view: GIFImageView, coordinator: ()) {
        view.stop()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GIFImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: proposal.height ?? 100)
    }
}

/// Loads a gif through the cache and animates it.
struct GIFView: View {
    let url: URL?
    var posterURL: URL?

    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let data, let url {
                AnimatedImage(data: data, url: url)
            } else {
                RemoteImage(url: posterURL, maxPixelWidth: 800)
                    .overlay {
                        if failed {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
            }
        }
        .task(id: url) {
            guard let url else { return }
            do {
                data = try await ImagePipeline.shared.data(url)
            } catch {
                if !error.isCancellation { failed = true }
            }
        }
    }
}

// MARK: - Video (joyreactor serves WebM, which only WebKit can play on iOS)

struct WebVideoView: UIViewRepresentable {
    let sources: [URL]
    var poster: URL?
    var muted = true

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.loadHTMLString(html, baseURL: URL(string: "https://joyreactor.cc/"))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.evaluateJavaScript("document.querySelectorAll('video').forEach(v => { v.pause(); v.removeAttribute('src'); v.load(); })")
        view.loadHTMLString("", baseURL: nil)
    }

    private var html: String {
        let sourceTags = sources.map { url -> String in
            let type = url.pathExtension == "webm" ? "video/webm" : "video/mp4"
            return "<source src=\"\(url.absoluteString)\" type=\"\(type)\">"
        }.joined()
        let posterAttr = poster.map { " poster=\"\($0.absoluteString)\"" } ?? ""
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>
        html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        video{width:100%;height:100%;object-fit:contain;background:#000;display:block}
        </style></head><body>
        <video autoplay loop playsinline controls \(muted ? "muted" : "") preload="auto"\(posterAttr)>\(sourceTags)</video>
        </body></html>
        """
    }
}

struct VideoAttributeView: View {
    let attribute: Attribute
    var autoplay: Bool

    @State private var playing = false

    var body: some View {
        ZStack {
            if playing {
                WebVideoView(sources: attribute.videoURLs, poster: attribute.posterURL)
            } else {
                RemoteImage(url: attribute.posterURL, maxPixelWidth: Display.pixelWidth)
                Button {
                    playing = true
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial.opacity(0.9), in: Circle())
                        .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .topLeading) {
            if !playing {
                Text(attribute.image.type == "GIF" ? "GIF" : "ВИДЕО")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .onAppear { if autoplay { playing = true } }
        .onDisappear { playing = false }
    }
}

// MARK: - Zoomable picture

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        maximumZoomScale = 5
        minimumZoomScale = 1
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        lastBoundsSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBoundsSize, let image = imageView.image, image.size.width > 0 else {
            centerContent()
            return
        }
        lastBoundsSize = bounds.size
        zoomScale = 1
        let width = bounds.width
        var height = width * image.size.height / image.size.width
        var fittedWidth = width
        if height < bounds.height || height <= bounds.height * 1.2 {
            // Fit whole picture on screen.
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            fittedWidth = image.size.width * scale
            height = image.size.height * scale
        }
        imageView.frame = CGRect(x: 0, y: 0, width: fittedWidth, height: height)
        contentSize = imageView.frame.size
        contentOffset = .zero
        centerContent()
    }

    private func centerContent() {
        let x = max((bounds.width - contentSize.width) / 2, 0)
        let y = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?

    func makeUIView(context: Context) -> ZoomScrollView { ZoomScrollView() }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.setImage(image)
    }
}

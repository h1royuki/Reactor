import SwiftUI
import UIKit
import ImageIO

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

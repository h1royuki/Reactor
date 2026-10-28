import SwiftUI
import UIKit
import WebKit

extension EnvironmentValues {
    /// Post that owns the media being rendered (used by the fullscreen video player).
    @Entry var currentPost: Post? = nil
}

/// Global sound state shared by all players, like Reddit.
@MainActor
@Observable
final class VideoAudio {
    static let shared = VideoAudio()
    var muted = true
}

// MARK: - Controller

/// Drives an HTML5 `<video>` inside a WKWebView (joyreactor serves WebM, which only WebKit can play on iOS).
@MainActor
@Observable
final class VideoController {
    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored weak var webView: WKWebView?

    func play() { run("v.play()") }
    func pause() { run("v.pause()") }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        currentTime = time
        run("v.currentTime = \(max(0, time))")
    }

    func setMuted(_ muted: Bool) {
        run("v.muted = \(muted)")
    }

    fileprivate func handle(_ body: [String: Any]) {
        let type = body["type"] as? String ?? ""
        if let t = body["t"] as? Double { currentTime = t }
        if let d = body["d"] as? Double, d.isFinite, d > 0 { duration = d }
        if let paused = body["paused"] as? Bool { isPlaying = !paused }
        switch type {
        case "waiting", "loadstart": isBuffering = true
        case "playing", "canplay", "seeked", "pause": isBuffering = false
        default: break
        }
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript("if (window.v) { \(script) }", completionHandler: nil)
    }
}

@MainActor
private final class VideoMessageProxy: NSObject, WKScriptMessageHandler {
    weak var controller: VideoController?

    init(controller: VideoController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        controller?.handle(body)
    }
}

struct WebVideoView: UIViewRepresentable {
    let controller: VideoController
    let sources: [URL]
    var poster: URL?
    var muted = true
    var startTime: Double = 0

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.userContentController.add(VideoMessageProxy(controller: controller), name: "video")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        // Gestures are handled by SwiftUI overlays.
        view.isUserInteractionEnabled = false
        controller.webView = view
        view.loadHTMLString(html, baseURL: URL(string: "https://joyreactor.cc/"))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        controller.webView = view
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        view.evaluateJavaScript("if (window.v) { v.pause(); v.removeAttribute('src'); v.load(); }", completionHandler: nil)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "video")
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
        html,body{margin:0;padding:0;background:transparent;height:100%;overflow:hidden}
        video{width:100%;height:100%;object-fit:contain;background:transparent;display:block}
        video::-webkit-media-controls{display:none !important}
        </style></head><body>
        <video autoplay loop playsinline webkit-playsinline disablepictureinpicture \(muted ? "muted" : "") preload="auto"\(posterAttr)>\(sourceTags)</video>
        <script>
        window.v = document.querySelector('video');
        const start = \(max(0, startTime));
        function send(type) {
          try {
            window.webkit.messageHandlers.video.postMessage({
              type: type, t: v.currentTime || 0, d: v.duration || 0, paused: v.paused
            });
          } catch (e) {}
        }
        ['loadstart','loadedmetadata','durationchange','canplay','play','playing','pause','waiting','seeked','timeupdate','ended']
          .forEach(function (e) { v.addEventListener(e, function () { send(e); }); });
        v.addEventListener('loadedmetadata', function () {
          if (start > 0 && start < v.duration) { v.currentTime = start; }
        }, { once: true });
        </script>
        </body></html>
        """
    }
}

enum VideoTime {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RoundControlButton: View {
    let icon: String
    var size: CGFloat = 68
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.45), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline (feed) player

/// Feed video: plays muted without controls. First tap shows a play/pause button,
/// tapping outside that button opens the fullscreen player.
struct VideoAttributeView: View {
    let attribute: Attribute
    var autoplay: Bool

    @Environment(\.currentPost) private var post
    @State private var controller = VideoController()
    @State private var active = false
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?
    @State private var fullscreen = false
    @State private var resumeAfterFullscreen = false

    private var audio: VideoAudio { .shared }

    var body: some View {
        ZStack {
            RemoteImage(url: attribute.posterURL, maxPixelWidth: Display.pixelWidth)

            if active {
                WebVideoView(controller: controller, sources: attribute.videoURLs,
                             poster: attribute.posterURL, muted: audio.muted)
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)

            if !active {
                RoundControlButton(icon: "play.fill") { start() }
            } else if showControls {
                RoundControlButton(icon: controller.isPlaying ? "pause.fill" : "play.fill") {
                    controller.toggle()
                    scheduleHide()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if controller.isBuffering {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.black.opacity(0.35), in: Circle())
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if active {
                Button {
                    audio.muted.toggle()
                } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.55), in: Circle())
                        .contentShape(Circle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if active, controller.duration > 0 {
                Text(VideoTime.format(max(controller.duration - controller.currentTime, 0)))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if !active {
                Text(attribute.image.type == "GIF" ? "GIF" : "ВИДЕО")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showControls)
        .onAppear { if autoplay { active = true } }
        .onDisappear {
            hideTask?.cancel()
            showControls = false
            if !fullscreen { active = false }
        }
        .onChange(of: audio.muted) { controller.setMuted(audio.muted) }
        .onChange(of: fullscreen) {
            if fullscreen {
                resumeAfterFullscreen = controller.isPlaying
                controller.pause()
            } else if resumeAfterFullscreen {
                controller.play()
            }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            VideoViewer(attribute: attribute, post: post, startTime: controller.currentTime)
        }
    }

    private func start() {
        active = true
        showControls = false
    }

    private func handleTap() {
        guard active else {
            start()
            return
        }
        if showControls {
            hideTask?.cancel()
            showControls = false
            fullscreen = true
        } else {
            showControls = true
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }
}

// MARK: - Fullscreen player

struct VideoViewer: View {
    let attribute: Attribute
    let post: Post?
    let startTime: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router: Router?
    @State private var controller = VideoController()
    @State private var chromeVisible = true
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0

    private var audio: VideoAudio { .shared }
    private var store: InteractionStore { .shared }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - Double(min(abs(dragOffset) / 400, 0.85)))
                .ignoresSafeArea()

            WebVideoView(controller: controller, sources: attribute.videoURLs, poster: attribute.posterURL,
                         muted: audio.muted, startTime: startTime)
                .aspectRatio(attribute.image.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: dragOffset)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { setChrome(!chromeVisible) }

            if chromeVisible {
                RoundControlButton(icon: controller.isPlaying ? "pause.fill" : "play.fill", size: 76) {
                    controller.toggle()
                    scheduleHide()
                }
                .transition(.opacity)
            } else if controller.isBuffering {
                ProgressView().tint(.white).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if chromeVisible { topBar.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if chromeVisible { bottomPanel.transition(.opacity) }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 140 || abs(value.predictedEndTranslation.height) > 400 {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { dragOffset = 0 }
                    }
                }
        )
        .animation(.easeOut(duration: 0.2), value: chromeVisible)
        .statusBarHidden(!chromeVisible)
        .environment(\.colorScheme, .dark)
        .onChange(of: audio.muted) { controller.setMuted(audio.muted) }
        .onChange(of: controller.isPlaying) { if controller.isPlaying { scheduleHide() } }
        .persistentSystemOverlays(.hidden)
        .presentationBackground(.clear)
    }

    private var topBar: some View {
        HStack {
            circleButton("xmark") { dismiss() }
            Spacer()
            if let tag = post?.tags.first?.name {
                Text(tag)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            Spacer()
            Menu {
                if let post {
                    Link(destination: post.webURL) {
                        Label("Открыть в Safari", systemImage: "safari")
                    }
                }
                if let video = attribute.videoURLs.first {
                    Button {
                        UIPasteboard.general.url = video
                        ToastCenter.shared.show("Ссылка на видео скопирована")
                    } label: {
                        Label("Скопировать ссылку на видео", systemImage: "link")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.14), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let post {
                HStack(spacing: 10) {
                    AvatarView(url: post.user.avatarURL, name: post.user.username, size: 30)
                    Text(post.user.username)
                        .font(.subheadline.weight(.semibold))
                }
                if let title = title(for: post) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 14) {
                Button {
                    controller.toggle()
                    scheduleHide()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Slider(value: Binding(get: { scrubbing ? scrubValue : min(controller.currentTime, max(controller.duration, 0.1)) },
                                      set: { scrubValue = $0 }),
                       in: 0...max(controller.duration, 0.1),
                       onEditingChanged: { editing in
                    if editing {
                        scrubValue = controller.currentTime
                        hideTask?.cancel()
                    } else {
                        controller.seek(to: scrubValue)
                        scheduleHide()
                    }
                    scrubbing = editing
                })
                .tint(.white)

                Text(VideoTime.format(scrubbing ? scrubValue : controller.currentTime))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 42, alignment: .trailing)

                Button {
                    audio.muted.toggle()
                    scheduleHide()
                } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            if let post {
                let state = store.state(for: post)
                HStack(spacing: 10) {
                    VoteControl(rating: state.rating, vote: state.vote, busy: store.pending.contains(post.id)) { plus in
                        Task { await store.vote(post: post, plus: plus) }
                    }
                    Button {
                        openComments(post)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                            Text("\(post.commentsCount)").monospacedDigit()
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    ShareLink(item: post.webURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 44, height: 34)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func title(for post: Post) -> String? {
        if let header = post.header, !header.isEmpty { return HTMLText.decodeEntities(header) }
        let text = ContentBuilder.plainText(html: post.text).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let tags = post.tags.prefix(3).map(\.name)
        return tags.isEmpty ? nil : tags.joined(separator: " · ")
    }

    private func openComments(_ post: Post) {
        dismiss()
        guard let router else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router.push(.post(post))
        }
    }

    private func setChrome(_ visible: Bool) {
        chromeVisible = visible
        if visible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard controller.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !scrubbing else { return }
            chromeVisible = false
        }
    }
}

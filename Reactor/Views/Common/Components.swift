import SwiftUI
import UIKit

enum Display {
    @MainActor static var pixelWidth: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let screen = scene?.screen
        let width = (screen?.bounds.width ?? 430) * (screen?.scale ?? 3)
        return min(max(width, 800), 2400)
    }
}

/// Async image backed by `ImagePipeline` (cache + downsampling).
struct RemoteImage: View {
    let url: URL?
    var maxPixelWidth: CGFloat = 1400
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, maxPixelWidth: CGFloat = 1400, contentMode: ContentMode = .fill) {
        self.url = url
        self.maxPixelWidth = maxPixelWidth
        self.contentMode = contentMode
        _image = State(initialValue: url.flatMap { ImagePipeline.shared.cachedImage($0, maxPixelWidth: maxPixelWidth) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .opacity(url == nil ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { failed = true; return }
            if image != nil { return }
            do {
                let loaded = try await ImagePipeline.shared.image(url, maxPixelWidth: maxPixelWidth)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            } catch {
                if !error.isCancellation { failed = true }
            }
        }
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 36

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Self.color(for: name).gradient)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .task(id: url) {
            guard let url else { return }
            image = try? await ImagePipeline.shared.image(url, maxPixelWidth: size * 3)
        }
    }

    static func color(for name: String) -> Color {
        let palette: [Color] = [.orange, .pink, .purple, .indigo, .blue, .teal, .green, .mint, .red, .brown]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}

struct TagChip: View {
    let name: String
    var highlighted = false

    var body: some View {
        NavigationLink(value: Route.tag(name)) {
            Text(name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(highlighted ? Color.white : Color.primary)
                .background(highlighted ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Повторить", action: retry)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct ToastOverlay: View {
    private var center: ToastCenter { .shared }

    var body: some View {
        VStack {
            if let message = center.message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct SectionSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(.systemGroupedBackground))
            .frame(height: 8)
    }
}

struct StatLabel: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

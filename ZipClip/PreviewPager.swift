import AVFoundation
import Photos
import SwiftUI
import UIKit

/// Full-screen pager like WeChat / Douyin: swipe between clips, select while watching.
struct PreviewPager: View {
    let videos: [LibraryVideo]
    let startIndex: Int
    @Binding var selected: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingDown = false

    private var dismissProgress: CGFloat {
        min(1, max(0, dragOffset / 280))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - Double(dismissProgress) * 0.55)
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { offset, video in
                    PreviewPage(
                        video: video,
                        isActive: offset == index && !isDraggingDown,
                        selected: selected.contains(video.id),
                        onToggle: { toggle(video) }
                    )
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: max(0, dragOffset))
            .scaleEffect(1 - dismissProgress * 0.08, anchor: .top)
            .clipShape(RoundedRectangle(cornerRadius: dismissProgress * 18, style: .continuous))

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .offset(y: max(0, dragOffset))
            .opacity(1 - Double(dismissProgress) * 1.2)
        }
        .statusBarHidden(true)
        .simultaneousGesture(dismissGesture)
        .onAppear {
            index = min(max(0, startIndex), max(0, videos.count - 1))
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = value.translation.height
                // Prefer vertical dismiss; leave shallow angles to the page swipe.
                guard dy > 0, dy > dx * 1.15 else {
                    if isDraggingDown {
                        dragOffset = 0
                        isDraggingDown = false
                    }
                    return
                }
                isDraggingDown = true
                dragOffset = dy
            }
            .onEnded { value in
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let shouldDismiss = isDraggingDown && (dy > 110 || predicted > 220)
                if shouldDismiss {
                    withAnimation(.easeOut(duration: 0.18)) {
                        dragOffset = UIScreen.main.bounds.height
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                        isDraggingDown = false
                    }
                }
            }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel(L10n.previewClose)

            Spacer()

            if videos.count > 1 {
                Text("\(index + 1)/\(videos.count)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: Capsule())
            }
        }
    }

    private var bottomBar: some View {
        let video = videos.indices.contains(index) ? videos[index] : nil
        let isSelected = video.map { selected.contains($0.id) } ?? false
        return HStack {
            if let video {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ClipFormat.clock(video.duration)) · \(ClipFormat.bytes(video.fileSize))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    if !video.isLocal {
                        Text(L10n.previewICloudBlocked)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Spacer()
            if let video, video.isLocal {
                Button {
                    toggle(video)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2.weight(.semibold))
                        Text(isSelected ? L10n.previewSelected : L10n.select)
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? Color.black : Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(isSelected ? Color.zip : Color.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? L10n.deselect : L10n.select)
            }
        }
    }

    private func toggle(_ video: LibraryVideo) {
        guard video.isLocal else { return }
        if selected.contains(video.id) {
            selected.remove(video.id)
        } else {
            selected.insert(video.id)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct PreviewPage: View {
    let video: LibraryVideo
    let isActive: Bool
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        ZStack {
            ImmersivePlayer(asset: video.asset, isActive: isActive)
            if selected {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.zip)
                            .padding(20)
                            .padding(.top, 48)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onToggle)
    }
}

private struct ImmersivePlayer: UIViewRepresentable {
    let asset: PHAsset
    let isActive: Bool

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        context.coordinator.attach(to: view)
        context.coordinator.load(asset)
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        if context.coordinator.assetID != asset.localIdentifier {
            context.coordinator.load(asset)
        }
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var assetID: String?
        private weak var container: PlayerContainerView?
        private var player: AVPlayer?
        private var endObserver: NSObjectProtocol?
        private var requestID = PHImageRequestID()
        private var wantsPlay = false

        func attach(to view: PlayerContainerView) {
            container = view
        }

        func load(_ asset: PHAsset) {
            assetID = asset.localIdentifier
            PHImageManager.default().cancelImageRequest(requestID)
            tearDownPlayer()
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .automatic
            requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self, self.assetID == asset.localIdentifier, let item else { return }
                    let player = AVPlayer(playerItem: item)
                    player.isMuted = false
                    self.player = player
                    self.container?.playerLayer.player = player
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { [weak player] _ in
                        player?.seek(to: .zero)
                        player?.play()
                    }
                    if self.wantsPlay {
                        player.play()
                    }
                }
            }
        }

        func setActive(_ active: Bool) {
            wantsPlay = active
            if active {
                player?.play()
            } else {
                player?.pause()
            }
        }

        private func tearDownPlayer() {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            player?.pause()
            player = nil
            container?.playerLayer.player = nil
        }

        deinit {
            PHImageManager.default().cancelImageRequest(requestID)
            tearDownPlayer()
        }
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

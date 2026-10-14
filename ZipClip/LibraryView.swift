import Photos
import SwiftUI
import UIKit

struct LibraryView: View {
    let videos: [LibraryVideo]
    let onStart: ([LibraryVideo]) -> Void

    @State private var selected: Set<String> = []
    @State private var previewIndex: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var selectableIDs: Set<String> {
        Set(videos.filter(\.isLocal).map(\.id))
    }

    private var allSelected: Bool {
        !selectableIDs.isEmpty && selectableIDs.isSubset(of: selected)
    }

    var body: some View {
        Group {
            if videos.isEmpty {
                Text(L10n.noneExceeding)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(L10n.libraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !videos.isEmpty {
                Button(allSelected ? L10n.deselectAll : L10n.selectAll) {
                    toggleAll()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                Button {
                    onStart(videos.filter { selected.contains($0.id) })
                } label: {
                    Text(L10n.startCount(selected.count))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.black)
                        .background(Color.zip, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewIndex != nil },
            set: { if !$0 { previewIndex = nil } }
        )) {
            PreviewPager(
                videos: videos,
                startIndex: previewIndex ?? 0,
                selected: $selected
            )
        }
    }

    private var grid: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let side = width.isFinite && width > 4 ? floor((width - 4) / 3) : 0
            if side >= 1 {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { offset, video in
                            VideoCell(
                                video: video,
                                side: side,
                                selected: selected.contains(video.id)
                            ) {
                                guard video.isLocal else { return }
                                if selected.contains(video.id) {
                                    selected.remove(video.id)
                                } else {
                                    selected.insert(video.id)
                                }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } onPreview: {
                                previewIndex = offset
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = selectableIDs
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct VideoCell: View {
    let video: LibraryVideo
    let side: CGFloat
    let selected: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void

    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    private var durationText: String { ClipFormat.clock(video.duration) }
    private var sizeText: String { ClipFormat.bytes(video.fileSize) }

    var body: some View {
        ZStack {
            thumbnail

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    if video.isLocal {
                        Button(action: onToggle) {
                            ZStack {
                                Circle()
                                    .fill(selected ? Color.zip : Color.black.opacity(0.28))
                                Circle()
                                    .strokeBorder(selected ? Color.zip : Color.white.opacity(0.9), lineWidth: 1.5)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(width: 22, height: 22)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selected ? L10n.deselect : L10n.select)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    chip(durationText)
                    Spacer(minLength: 0)
                    chip(sizeText)
                }
                .allowsHitTesting(false)
            }
            .padding(6)
        }
        .frame(width: side, height: side)
        .clipped()
        .scaleEffect(selected ? 0.96 : 1)
        .animation(.spring(duration: 0.25), value: selected)
        .opacity(video.isLocal ? 1 : 0.45)
        .task(id: "\(video.id)-\(Int(side))") {
            guard side >= 1 else { return }
            image = await PhotoLibraryService.thumbnail(for: video.asset, side: side, scale: scale)
        }
    }

    private var thumbnail: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            if !video.isLocal {
                Text(L10n.iCloudOnly)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPreview)
        .accessibilityLabel("\(durationText)，\(sizeText)")
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45), in: Capsule())
    }
}

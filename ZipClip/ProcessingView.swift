import AVFoundation
import Photos
import SwiftUI
import UIKit

struct ProcessingView: View {
    let videos: [LibraryVideo]
    let settings: CompressSettings
    let onFinishedReturnHome: () -> Void

    @StateObject private var model = BatchProcessor()
    @State private var runTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            thumbnail
            if model.finished {
                Image(systemName: model.successCount > 0 ? "checkmark" : "exclamationmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.zip)
                    .symbolEffect(.bounce, value: model.finished)
            } else {
                LightSlit(progress: model.progress, reduceMotion: reduceMotion)
                    .padding(.horizontal, 40)
                Text("\(Int((min(1, model.progress) * 100).rounded()))%")
                    .font(.system(.title, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: model.progress))
            }
            Text(model.statusLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if model.finished {
                Text(resultLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            if model.finished {
                Button(action: onFinishedReturnHome) {
                    Text(L10n.processingDone)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.black)
                        .background(Color.zip, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            } else {
                Button {
                    runTask?.cancel()
                } label: {
                    Text(L10n.processingCancel)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.primary)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(L10n.processingTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if model.finished {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.processingBack, action: onFinishedReturnHome)
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.finished) { _, finished in
            finished && model.successCount > 0
        }
        .task(id: videos.map(\.id)) {
            guard !videos.isEmpty else { return }
            let task = Task {
                await model.run(videos: videos, settings: settings)
            }
            runTask = task
            await task.value
        }
    }

    private var resultLine: String {
        L10n.resultLine(
            success: model.successCount,
            failure: model.failureCount,
            deleted: model.deletedCount,
            deleteEnabled: settings.deleteOriginal
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = model.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .frame(width: 168, height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LightSlit: View {
    var progress: Double
    var reduceMotion: Bool
    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width)
            let clamped = min(1, max(0, progress))
            let filled = width.isFinite ? width * clamped : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.zip)
                    .frame(width: max(0, filled))
                if !reduceMotion, clamped > 0.01, clamped < 1 {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 22, height: 2)
                        .shadow(color: Color.zip.opacity(glow ? 0.9 : 0.35), radius: glow ? 8 : 3)
                        .offset(x: max(0, filled - 11))
                }
            }
        }
        .frame(height: 2)
        .animation(reduceMotion ? nil : .linear(duration: 0.12), value: progress)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

@MainActor
final class BatchProcessor: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusLine = L10n.processingWorking
    @Published var thumbnail: UIImage?
    @Published var finished = false
    @Published var successCount = 0
    @Published var failureCount = 0
    @Published var deletedCount = 0
    @Published var isRunning = false

    private let processor = VideoProcessor()

    private struct SaveOutcome: Sendable {
        var saved: Bool
        var assetID: String?
    }

    func run(videos: [LibraryVideo], settings: CompressSettings) async {
        guard !isRunning else { return }
        guard !videos.isEmpty else { return }

        isRunning = true
        finished = false
        progress = 0
        successCount = 0
        failureCount = 0
        deletedCount = 0
        statusLine = L10n.processingWorking
        let total = videos.count

        let durationTarget: TimeInterval? = settings.durationSeconds
        let bytesTarget: Int64? = settings.targetBytes
        var originalsToDelete: [PHAsset] = []
        var pendingSave: Task<SaveOutcome, Never>?

        var current = await PhotoLibraryService.loadAsset(videos[0].asset)
        for index in videos.indices {
            let video = videos[index]
            let asset = current
            let hasNext = index + 1 < total
            async let upcoming: AVAsset? = {
                guard hasNext else { return nil as AVAsset? }
                return await PhotoLibraryService.loadAsset(videos[index + 1].asset)
            }()

            if Task.isCancelled {
                _ = await upcoming
                break
            }
            statusLine = L10n.processingItem(index + 1, total)
            thumbnail = await PhotoLibraryService.thumbnail(for: video.asset, side: 168, scale: UIScreen.main.scale)

            guard let asset else {
                failureCount += 1
                current = await upcoming
                continue
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            var stop = false
            do {
                let gate = ProgressGateBox()
                let assetID = video.id
                try await processor.export(
                    asset: asset,
                    sourceBytes: video.fileSize > 0 ? video.fileSize : nil,
                    targetDuration: durationTarget,
                    targetBytes: bytesTarget,
                    to: url
                ) { fraction in
                    let overall = (Double(index) + fraction) / Double(total)
                    guard gate.allow(force: fraction >= 0.999) else { return }
                    Task { @MainActor in
                        self.progress = overall
                    }
                }
                // Keep at most one save in flight so temp files don't pile up.
                if let pendingSave {
                    let outcome = await pendingSave.value
                    apply(outcome, originals: &originalsToDelete, videos: videos, deleteOriginal: settings.deleteOriginal)
                }
                pendingSave = Task {
                    do {
                        try await PhotoLibraryService.saveVideo(at: url)
                        try? FileManager.default.removeItem(at: url)
                        return SaveOutcome(saved: true, assetID: assetID)
                    } catch {
                        try? FileManager.default.removeItem(at: url)
                        return SaveOutcome(saved: false, assetID: nil)
                    }
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: url)
                stop = true
            } catch let error as ClipError where error == .cancelled {
                try? FileManager.default.removeItem(at: url)
                stop = true
            } catch {
                try? FileManager.default.removeItem(at: url)
                failureCount += 1
            }
            current = await upcoming
            if stop { break }
        }

        if let pendingSave, !Task.isCancelled {
            statusLine = L10n.processingSaving
            let outcome = await pendingSave.value
            apply(outcome, originals: &originalsToDelete, videos: videos, deleteOriginal: settings.deleteOriginal)
        } else if let pendingSave {
            let outcome = await pendingSave.value
            apply(outcome, originals: &originalsToDelete, videos: videos, deleteOriginal: settings.deleteOriginal)
        }

        if settings.deleteOriginal, !originalsToDelete.isEmpty, !Task.isCancelled {
            statusLine = L10n.processingDeleting
            do {
                try await PhotoLibraryService.deleteAssets(originalsToDelete)
                deletedCount = originalsToDelete.count
            } catch {
                deletedCount = 0
            }
        }

        progress = 1
        finished = true
        isRunning = false
        if Task.isCancelled {
            statusLine = L10n.processingCancelled
        } else if successCount > 0 {
            statusLine = settings.deleteOriginal && deletedCount > 0
                ? L10n.processingSavedAndDeleted
                : L10n.processingSaved
        } else {
            statusLine = L10n.processingFailed
        }
    }

    private func apply(
        _ outcome: SaveOutcome,
        originals: inout [PHAsset],
        videos: [LibraryVideo],
        deleteOriginal: Bool
    ) {
        if outcome.saved {
            successCount += 1
            if deleteOriginal, let id = outcome.assetID, let original = videos.first(where: { $0.id == id })?.asset {
                originals.append(original)
            }
        } else {
            failureCount += 1
        }
    }
}

private final class ProgressGateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var last = CFAbsoluteTimeGetCurrent() - 1

    func allow(force: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        if !force && now - last < 0.1 { return false }
        last = now
        return true
    }
}

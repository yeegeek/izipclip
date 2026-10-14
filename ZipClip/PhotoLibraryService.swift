import AVFoundation
import Photos
import UIKit

struct LibraryVideo: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let duration: Double
    let fileSize: Int64
    let isLocal: Bool

    /// Compact rate for the grid, e.g. "1.33×". Size-only clips show "1×".
    func rateLabel(settings: CompressSettings) -> String {
        if duration > settings.durationSeconds {
            let plan = SpeedPlan.make(sourceDuration: duration, targetDuration: settings.durationSeconds)
            if plan.segments.count == 1 {
                return String(format: "%.2f×", plan.segments[0].rate)
            }
            return String(format: "%.1f×", plan.segments[1].rate)
        }
        return "1×"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LibraryVideo, rhs: LibraryVideo) -> Bool {
        lhs.id == rhs.id
    }
}

enum PhotoLibraryService {
    /// Scans the library off the main queue and prefetches metadata so size reads
    /// do not hitch the UI thread.
    static func videosExceeding(settings: CompressSettings) async -> [LibraryVideo] {
        let durationFloor = settings.listDurationFloor
        let byteFloor = settings.listByteFloor
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            if #available(iOS 27.0, *) {
                options.prefetchAssetExtendedMetadata = true
            }
            let result = PHAsset.fetchAssets(with: .video, options: options)
            var videos: [LibraryVideo] = []
            videos.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                let duration = asset.duration
                let size = fileSize(of: asset)
                // Hide when under both floors (e.g. <61s and <26MB for 60s/25MB).
                let exceedsDuration = duration >= durationFloor
                let exceedsSize = size > 0 && size >= byteFloor
                guard exceedsDuration || exceedsSize else { return }
                videos.append(
                    LibraryVideo(
                        id: asset.localIdentifier,
                        asset: asset,
                        duration: duration,
                        fileSize: size,
                        isLocal: isLocallyAvailable(asset)
                    )
                )
            }
            return videos
        }.value
    }

    static func loadAsset(_ asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    static func saveVideo(at url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    static func deleteAssets(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    static func thumbnail(for asset: PHAsset, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let pixels = side * max(scale, 1)
        let target = CGSize(width: pixels, height: pixels)
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            let box = ResumeOnceBox(continuation)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    box.resume(returning: nil)
                    return
                }
                box.resume(returning: image)
            }
        }
    }

    private static func fileSize(of asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first { $0.type == .video || $0.type == .fullSizeVideo } ?? resources.first
        guard let resource else { return 0 }
        if #available(iOS 27.0, *), let dataSize = resource.dataSize {
            return Int64(dataSize)
        }
        return integerValue(resource, key: "fileSize")
    }

    private static func isLocallyAvailable(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else { return false }
        let selector = NSSelectorFromString("locallyAvailable")
        guard resource.responds(to: selector) else { return true }
        return (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
    }

    private static func integerValue(_ resource: PHAssetResource, key: String) -> Int64 {
        let selector = NSSelectorFromString(key)
        guard resource.responds(to: selector) else { return 0 }
        let value = resource.value(forKey: key)
        if let number = value as? NSNumber { return number.int64Value }
        if let number = value as? Int64 { return number }
        if let number = value as? Int { return Int64(number) }
        if let number = value as? UInt64 { return Int64(number) }
        return 0
    }
}

private final class ResumeOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: UIImage?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

import Foundation

/// Central keys for the String Catalog. Edit translations in `Localizable.xcstrings`.
enum L10n {
    static var appName: String { String(localized: "app_name") }
    static var deleteOriginal: String { String(localized: "home.delete_original") }
    static var duration: String { String(localized: "home.duration") }
    static var size: String { String(localized: "home.size") }
    static var unitSeconds: String { String(localized: "home.unit_seconds") }
    static var unitMB: String { String(localized: "home.unit_mb") }
    static var selectVideos: String { String(localized: "home.select_videos") }
    static var scanning: String { String(localized: "home.scanning") }
    static var needPhotos: String { String(localized: "home.need_photos") }
    static var openPhotosSettings: String { String(localized: "home.open_photos_settings") }
    static var noneExceeding: String { String(localized: "home.none_exceeding") }

    static var libraryTitle: String { String(localized: "library.title") }
    static var selectAll: String { String(localized: "library.select_all") }
    static var deselectAll: String { String(localized: "library.deselect_all") }
    static var start: String { String(localized: "library.start") }
    static var select: String { String(localized: "library.select") }
    static var deselect: String { String(localized: "library.deselect") }
    static var iCloudOnly: String { String(localized: "library.icloud_only") }

    static var previewClose: String { String(localized: "preview.close") }
    static var previewSelected: String { String(localized: "preview.selected") }
    static var previewICloudBlocked: String { String(localized: "preview.icloud_blocked") }

    static var processingTitle: String { String(localized: "processing.title") }
    static var processingDone: String { String(localized: "processing.done") }
    static var processingBack: String { String(localized: "processing.back") }
    static var processingCancel: String { String(localized: "processing.cancel") }
    static var processingWorking: String { String(localized: "processing.working") }
    static var processingSaving: String { String(localized: "processing.saving") }
    static var processingDeleting: String { String(localized: "processing.deleting") }
    static var processingSaved: String { String(localized: "processing.saved") }
    static var processingSavedAndDeleted: String { String(localized: "processing.saved_deleted") }
    static var processingFailed: String { String(localized: "processing.failed") }
    static var processingCancelled: String { String(localized: "processing.cancelled") }

    static func processingItem(_ index: Int, _ total: Int) -> String {
        String(format: String(localized: "processing.item_format"), index, total)
    }

    static func resultLine(success: Int, failure: Int, deleted: Int?, deleteEnabled: Bool) -> String {
        var parts = [
            String(format: String(localized: "processing.success_format"), success),
            String(format: String(localized: "processing.failure_format"), failure),
        ]
        if deleteEnabled, let deleted {
            parts.append(String(format: String(localized: "processing.deleted_format"), deleted))
        }
        return parts.joined(separator: String(localized: "common.list_separator"))
    }

    static func startCount(_ count: Int) -> String {
        String(format: String(localized: "library.start_format"), count)
    }

    static func speedUniform(_ rate: Double) -> String {
        String(format: String(localized: "speed.uniform_format"), rate)
    }

    static func speedSegmented(_ middle: Double) -> String {
        String(format: String(localized: "speed.segmented_format"), middle)
    }

    static var speedSizeOnly: String { String(localized: "speed.size_only") }
}

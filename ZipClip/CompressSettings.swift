import Foundation

struct CompressSettings: Hashable, Codable {
    /// Target clip length. Short-form range keeps speed-up usable.
    var durationSeconds: Double = 60
    /// Target file size. Messaging-friendly ceiling without pretending 200MB is "small".
    var sizeMB: Double = 25
    var deleteOriginal: Bool = false

    static let durationRange: ClosedRange<Double> = 15...300
    static let sizeRange: ClosedRange<Double> = 5...300
    static let durationStep: Double = 5
    static let sizeStep: Double = 1

    var targetBytes: Int64 {
        Int64(sizeMB * 1024 * 1024)
    }

    /// Picker slack: with 60s / 25MB, hide clips under 61s and under 26MB.
    /// Stops near-limit videos (60.01s, 25.1MB) from cluttering the list.
    var listDurationFloor: Double {
        durationSeconds + 1
    }

    var listByteFloor: Int64 {
        Int64((sizeMB + 1) * 1024 * 1024)
    }

    private static let storageKey = "zipclip.settings.v2"

    static func load() -> CompressSettings {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(CompressSettings.self, from: data) {
            return settings.sanitized()
        }
        // Migrate from older Zip Clip / FlashClip settings blobs when present.
        for key in ["zipclip.settings.v1", "flashclip.settings.v2", "flashclip.settings.v1"] {
            if let data = UserDefaults.standard.data(forKey: key),
               let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
                return CompressSettings(
                    durationSeconds: legacy.durationSeconds,
                    sizeMB: legacy.sizeMB,
                    deleteOriginal: legacy.deleteOriginal
                ).sanitized()
            }
        }
        return CompressSettings()
    }

    func persist() {
        let clean = sanitized()
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func sanitized() -> CompressSettings {
        var copy = self
        copy.durationSeconds = Self.durationRange.clamp(durationSeconds.rounded())
        copy.sizeMB = Self.sizeRange.clamp(sizeMB.rounded())
        return copy
    }
}

private struct LegacySettings: Codable {
    var durationSeconds: Double = 60
    var sizeMB: Double = 25
    var deleteOriginal: Bool = false
}

private extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}

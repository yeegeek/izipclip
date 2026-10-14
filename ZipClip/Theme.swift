import SwiftUI

extension Color {
    static let zip = Color(red: 245.0 / 255, green: 193.0 / 255, blue: 108.0 / 255)
}

enum ClipFormat {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "—" }
        let mb = Double(value) / 1_048_576
        if mb >= 100 { return String(format: "%.0f MB", mb) }
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }

    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

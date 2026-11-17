import Foundation

/// Định dạng và đọc số liệu (giống ui/common/Format.kt bên Android).
enum Format {
    /// 125 -> "2:05", 3725 -> "1:02:05".
    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 1530 -> "1,5 N lượt xem".
    static func views(_ count: Int) -> String {
        guard count > 0 else { return "" }
        func short(_ v: Double, _ unit: String) -> String {
            String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") + " " + unit
        }
        let text: String
        switch count {
        case 1_000_000_000...: text = short(Double(count) / 1e9, "T")
        case 1_000_000...: text = short(Double(count) / 1e6, "Tr")
        case 1_000...: text = short(Double(count) / 1e3, "N")
        default: text = "\(count)"
        }
        return text + " lượt xem"
    }

    /// "12:34" / "1:02:03" -> số giây.
    static func parseDuration(_ text: String?) -> Int {
        guard let text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3 else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// "1.234.567 lượt xem" -> 1234567 (bỏ mọi ký tự không phải số).
    static func parseCount(_ text: String?) -> Int {
        guard let text else { return 0 }
        return Int(text.filter(\.isNumber)) ?? 0
    }
}

import Foundation

// Các model của app, giống bản Android (domain/model/Models.kt).

/// Một video trong danh sách.
struct VideoSummary: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let channelName: String
    let thumbnailURL: URL?
    let durationSeconds: Int
    let viewCount: Int
}

/// Thông tin chi tiết một video, kèm video liên quan.
struct VideoDetail {
    let summary: VideoSummary
    let description: String
    let related: [VideoSummary]
}

/// Một video trong lịch sử xem.
struct WatchHistoryEntry: Codable, Identifiable {
    var video: VideoSummary
    var positionSeconds: Double
    var lastWatchedAt: Date
    /// Video liên quan lưu lúc xem: nguồn cho "Đề xuất cho bạn".
    var related: [VideoSummary]

    var id: String { video.id }

    /// Tỉ lệ đã xem 0...1 (0 nếu chưa biết thời lượng).
    var progress: Double {
        guard video.durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / Double(video.durationSeconds), 0), 1)
    }

    /// Xem gần hết thì coi như xong: mở lại phát từ đầu.
    var isFinished: Bool { progress >= 0.95 }
}

/// Các hàng "thịnh hành" trên trang chủ.
enum TrendingKind: String, Codable, CaseIterable {
    case MUSIC, LIVE, GAMING, MOVIES, PODCASTS

    var title: String {
        switch self {
        case .MUSIC: return "🎵 Âm nhạc thịnh hành"
        case .LIVE: return "🔴 Đang trực tiếp"
        case .GAMING: return "🎮 Trò chơi thịnh hành"
        case .MOVIES: return "🎬 Phim & trailer"
        case .PODCASTS: return "🎙 Podcast thịnh hành"
        }
    }

    /// Trên iOS dùng tìm kiếm tương đương (không có sẵn mục thịnh hành như NewPipe).
    var query: String {
        switch self {
        case .MUSIC: return "nhạc Việt thịnh hành mới nhất"
        case .LIVE: return "trực tiếp"
        case .GAMING: return "game thịnh hành"
        case .MOVIES: return "trailer phim mới"
        case .PODCASTS: return "podcast tiếng Việt"
        }
    }

    var liveOnly: Bool { self == .LIVE }
}

/// Bản iOS mới nhất (đọc từ config.json trên GitHub).
struct IOSRelease {
    let build: Int
    let version: String
    let ipaURL: URL
    let notes: [String]
}

/// Cấu hình đọc từ xa, dùng chung file config.json với bản Android.
struct RemoteConfig {
    var iosRelease: IOSRelease?
    var topics: [(name: String, query: String)]
    var trending: [TrendingKind]

    static let `default` = RemoteConfig(
        iosRelease: nil,
        topics: [
            ("Âm nhạc", "nhạc Việt hay nhất"),
            ("Bolero", "nhạc bolero"),
            ("Hoạt hình", "phim hoạt hình thiếu nhi"),
            ("Nấu ăn", "dạy nấu ăn món ngon"),
            ("Tin tức", "tin tức hôm nay"),
            ("Hài", "hài hước"),
            ("Du lịch", "du lịch Việt Nam"),
        ],
        trending: [.MUSIC, .LIVE, .MOVIES]
    )
}

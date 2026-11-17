import Foundation
import Observation

/// Lịch sử xem, lưu trong máy (file JSON trong thư mục Application Support).
/// Tương đương RoomHistoryRepository bên Android.
@MainActor
@Observable
final class HistoryStore {
    /// Mới xem nhất ở đầu.
    private(set) var entries: [WatchHistoryEntry] = []

    private let fileURL: URL
    private static let maxEntries = 500
    private static let relatedPerVideo = 20
    private static let recentSources = 5

    init(fileName: String = "history.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(fileName)
        load()
    }

    var continueWatching: [WatchHistoryEntry] {
        Array(entries.filter { $0.positionSeconds > 0 && !$0.isFinished }.prefix(10))
    }

    func entry(for id: String) -> WatchHistoryEntry? {
        entries.first { $0.id == id }
    }

    func progress(of id: String) -> Double? {
        entry(for: id)?.progress
    }

    /// Ghi nhận bắt đầu xem (cập nhật dòng cũ nếu đã xem trước đó).
    func recordWatch(_ detail: VideoDetail, position: Double) {
        entries.removeAll { $0.id == detail.summary.id }
        entries.insert(
            WatchHistoryEntry(
                video: detail.summary,
                positionSeconds: position,
                lastWatchedAt: Date(),
                related: Array(detail.related.prefix(Self.relatedPerVideo))
            ),
            at: 0
        )
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
    }

    /// Cập nhật vị trí đang xem; biết thời lượng thật thì lưu luôn.
    func updatePosition(_ id: String, position: Double, duration: Double?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].positionSeconds = position
        entries[index].lastWatchedAt = Date()
        if let duration, duration.isFinite, duration > 0, entries[index].video.durationSeconds == 0 {
            let v = entries[index].video
            entries[index].video = VideoSummary(
                id: v.id, title: v.title, channelName: v.channelName, thumbnailURL: v.thumbnailURL,
                durationSeconds: Int(duration), viewCount: v.viewCount
            )
        }
        save()
    }

    func delete(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// "Đề xuất cho bạn": trộn video liên quan của các video xem gần đây, bỏ video đã xem.
    func recommendations(limit: Int = 30) -> [VideoSummary] {
        let watched = Set(entries.map(\.id))
        var score: [String: Double] = [:]
        var video: [String: VideoSummary] = [:]
        var channelCount: [String: Int] = [:]

        for source in entries.prefix(Self.recentSources) {
            for (rank, item) in source.related.enumerated() where !watched.contains(item.id) {
                score[item.id, default: 0] += Double(Self.relatedPerVideo - rank)
                video[item.id] = item
                channelCount[item.channelName, default: 0] += 1
            }
        }
        return score
            .map { id, s in (id, s + Double(channelCount[video[id]!.channelName] ?? 0) * 0.5) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .compactMap { video[$0.0] }
    }

    // MARK: - Lưu file

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([WatchHistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

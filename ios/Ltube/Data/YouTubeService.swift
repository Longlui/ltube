import Foundation
import YouTubeKit

/// Cổng lấy dữ liệu YouTube của bản iOS (tương đương YoutubeSource bên Android).
///
/// Cơ chế không quảng cáo: YouTubeKit chỉ trả về link luồng hình/tiếng của video;
/// app phát thẳng bằng AVPlayer, không đọc phần quảng cáo.
struct YouTubeService {
    private let innerTube = InnerTubeClient()

    func search(_ query: String, liveOnly: Bool = false) async throws -> [VideoSummary] {
        try await innerTube.search(query, liveOnly: liveOnly)
    }

    func trending(_ kind: TrendingKind) async throws -> [VideoSummary] {
        try await innerTube.search(kind.query, liveOnly: kind.liveOnly)
    }

    func detail(videoID: String) async throws -> VideoDetail {
        let next = try await innerTube.next(videoID: videoID)
        var summary = next.summary
        if summary == nil, let meta = try? await YouTube(videoID: videoID).metadata {
            summary = VideoSummary(
                id: videoID, title: meta.title, channelName: "",
                thumbnailURL: meta.thumbnail?.url, durationSeconds: 0, viewCount: 0
            )
        }
        guard let summary else { throw LtubeError.badResponse }
        return VideoDetail(summary: summary, description: next.description, related: next.related)
    }

    /// Link phát: livestream dùng HLS; video thường dùng luồng có sẵn cả hình lẫn tiếng
    /// mà iPhone tự giải mã được, chọn độ phân giải cao nhất.
    func playbackURL(videoID: String) async throws -> URL {
        do {
            return try await findPlaybackURL(videoID: videoID)
        } catch let error as YouTubeKitError {
            throw LtubeError.youtube(error)
        }
    }

    private func findPlaybackURL(videoID: String) async throws -> URL {
        let video = YouTube(videoID: videoID, methods: [.local])
        if let live = try? await video.livestreams.first(where: { $0.streamType == .hls }) {
            return live.url
        }
        let candidates = try await video.streams
            .filter { $0.includesVideoAndAudioTrack && $0.isNativelyPlayable }
            .sorted { ($0.videoResolution ?? 0) > ($1.videoResolution ?? 0) }
        guard let best = candidates.first else { throw LtubeError.noPlayableStream }
        return best.url
    }
}

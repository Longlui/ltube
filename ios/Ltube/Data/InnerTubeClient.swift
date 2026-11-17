import Foundation

/// Gọi API nội bộ của YouTube (InnerTube) để tìm kiếm và lấy video liên quan.
/// Phần lấy luồng phát do thư viện YouTubeKit lo (xem YouTubeService).
struct InnerTubeClient {
    private let session: URLSession
    private static let base = URL(string: "https://www.youtube.com/youtubei/v1/")!
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:153.0) Gecko/20100101 Firefox/153.0"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - API

    /// Tìm video. `liveOnly` = chỉ lấy livestream (bộ lọc "Trực tiếp" của YouTube).
    func search(_ query: String, liveOnly: Bool = false) async throws -> [VideoSummary] {
        var body: [String: Any] = ["query": query]
        if liveOnly { body["params"] = "EgJAAQ%3D%3D".removingPercentEncoding ?? "EgJAAQ==" }
        let json = try await post("search", body: body)
        return JSONWalker.collect(json, keys: ["videoRenderer"]).compactMap(Self.parseVideoRenderer)
    }

    /// Thông tin video (tiêu đề, kênh, lượt xem, mô tả) và danh sách video liên quan.
    func next(videoID: String) async throws -> (summary: VideoSummary?, description: String, related: [VideoSummary]) {
        let json = try await post("next", body: ["videoId": videoID])

        let primary = JSONWalker.collect(json, keys: ["videoPrimaryInfoRenderer"]).first
        let secondary = JSONWalker.collect(json, keys: ["videoSecondaryInfoRenderer"]).first
        let title = JSONWalker.text(primary?["title"])
        let channel = JSONWalker.text(
            (secondary?["owner"] as? [String: Any]).flatMap { $0["videoOwnerRenderer"] as? [String: Any] }?["title"]
        )
        let viewText = JSONWalker.text(
            ((primary?["viewCount"] as? [String: Any])?["videoViewCountRenderer"] as? [String: Any])?["viewCount"]
        )
        let description = JSONWalker.text(secondary?["attributedDescription"]) ?? ""

        let summary = title.map {
            VideoSummary(
                id: videoID, title: $0, channelName: channel ?? "",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"),
                durationSeconds: 0, viewCount: Format.parseCount(viewText)
            )
        }

        // YouTube đã chuyển danh sách liên quan sang "lockupViewModel"; giữ cả dạng cũ để dự phòng
        let lockups = JSONWalker.collect(json, keys: ["lockupViewModel"]).compactMap(Self.parseLockup)
        let compact = JSONWalker.collect(json, keys: ["compactVideoRenderer"]).compactMap(Self.parseVideoRenderer)
        var seen = Set<String>([videoID])
        let related = (lockups + compact).filter { seen.insert($0.id).inserted }
        return (summary, description, related)
    }

    // MARK: - HTTP

    private func post(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB",
                "clientVersion": "2.20251101.01.00",
                "hl": "vi",
                "gl": "VN",
            ],
        ]
        var request = URLRequest(url: Self.base.appendingPathComponent(endpoint).appending(queryItems: [
            URLQueryItem(name: "prettyPrint", value: "false"),
        ]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("vi-VN,vi;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LtubeError.http(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LtubeError.badResponse
        }
        return json
    }

    // MARK: - Đọc dữ liệu

    /// Dạng cũ: videoRenderer / compactVideoRenderer.
    private static func parseVideoRenderer(_ r: [String: Any]) -> VideoSummary? {
        guard let id = r["videoId"] as? String, let title = JSONWalker.text(r["title"]) else { return nil }
        let channel = JSONWalker.text(r["ownerText"]) ?? JSONWalker.text(r["longBylineText"])
            ?? JSONWalker.text(r["shortBylineText"]) ?? ""
        let thumbs = ((r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]) ?? []
        let thumb = (thumbs.last?["url"] as? String).flatMap(URL.init(string:))
        return VideoSummary(
            id: id, title: title, channelName: channel, thumbnailURL: thumb,
            durationSeconds: Format.parseDuration(JSONWalker.text(r["lengthText"])),
            viewCount: Format.parseCount(JSONWalker.text(r["viewCountText"]))
        )
    }

    /// Dạng mới: lockupViewModel (danh sách liên quan từ 2025).
    private static func parseLockup(_ l: [String: Any]) -> VideoSummary? {
        guard (l["contentType"] as? String) == "LOCKUP_CONTENT_TYPE_VIDEO",
              let id = l["contentId"] as? String else { return nil }
        let meta = (l["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        guard let title = JSONWalker.text(meta?["title"]) else { return nil }

        // Dòng thông tin: [kênh] / [lượt xem • thời gian]
        let rows = ((((meta?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"]) as? [[String: Any]]) ?? []
        let parts = rows.map { row in ((row["metadataParts"] as? [[String: Any]]) ?? []).compactMap { JSONWalker.text($0["text"]) } }
        let channel = parts.first?.first ?? ""
        let views = parts.dropFirst().first?.first

        let badges = JSONWalker.collect(l["contentImage"] as Any, keys: ["thumbnailBadgeViewModel"])
        let duration = badges.compactMap { $0["text"] as? String }.first

        let sources = JSONWalker.collect(l["contentImage"] as Any, keys: ["image"])
            .compactMap { $0["sources"] as? [[String: Any]] }.first ?? []
        let thumb = (sources.last?["url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")

        return VideoSummary(
            id: id, title: title, channelName: channel, thumbnailURL: thumb,
            durationSeconds: Format.parseDuration(duration), viewCount: Format.parseCount(views)
        )
    }
}

enum LtubeError: LocalizedError {
    case http(Int)
    case badResponse
    case noPlayableStream

    var errorDescription: String? {
        switch self {
        case .http(let code): return "YouTube trả lỗi \(code). Thử lại sau ít phút."
        case .badResponse: return "Dữ liệu YouTube không đọc được. Có thể cần cập nhật app."
        case .noPlayableStream: return "Không tìm được luồng phát cho video này."
        }
    }
}

/// Tiện ích duyệt JSON lồng nhau của YouTube.
enum JSONWalker {
    /// Thu thập mọi object nằm dưới các khoá `keys`, ở bất kỳ độ sâu nào.
    static func collect(_ node: Any, keys: Set<String>) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ n: Any) {
            if let dict = n as? [String: Any] {
                for (k, v) in dict {
                    if keys.contains(k), let obj = v as? [String: Any] { out.append(obj) }
                    walk(v)
                }
            } else if let arr = n as? [Any] {
                arr.forEach(walk)
            }
        }
        walk(node)
        return out
    }

    /// Đọc chữ từ các dạng YouTube hay dùng: simpleText, runs[], content.
    static func text(_ node: Any?) -> String? {
        if let s = node as? String { return s }
        guard let d = node as? [String: Any] else { return nil }
        if let s = d["simpleText"] as? String { return s }
        if let s = d["content"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}

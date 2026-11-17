import Foundation

/// Đọc config.json trên GitHub (dùng chung với bản Android).
/// Mất mạng hoặc file lỗi thì dùng cấu hình mặc định.
struct RemoteConfigService {
    static let url = URL(string: "https://raw.githubusercontent.com/Longlui/ltube/main/config.json")!

    func load() async -> RemoteConfig {
        var request = URLRequest(url: Self.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .default
        }
        var config = RemoteConfig.default

        if let topics = root["topics"] as? [[String: Any]] {
            let parsed = topics.compactMap { t -> (String, String)? in
                guard let name = t["name"] as? String, let query = t["query"] as? String else { return nil }
                return (name, query)
            }
            if !parsed.isEmpty { config.topics = parsed.map { (name: $0.0, query: $0.1) } }
        }
        if let trending = root["trending"] as? [String] {
            config.trending = trending.compactMap(TrendingKind.init(rawValue:))
        }
        if let ios = root["ios"] as? [String: Any],
           let build = ios["build"] as? Int,
           let version = ios["version"] as? String,
           let urlString = ios["ipaUrl"] as? String, let ipaURL = URL(string: urlString) {
            config.iosRelease = IOSRelease(
                build: build, version: version, ipaURL: ipaURL,
                notes: (ios["notes"] as? [String]) ?? []
            )
        }
        return config
    }
}

import AVFoundation
import SwiftUI

/// Các màn hình của app.
enum Route: Hashable {
    case player(String)
    case history
}

@main
struct LtubeApp: App {
    @State private var history = HistoryStore()
    @State private var path: [Route] = []

    init() {
        // Cho phép phát tiếng khi khoá màn hình / chuyển app (cần UIBackgroundModes: audio)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(path: $path)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .player(let id):
                            PlayerScreen(videoID: id, path: $path)
                        case .history:
                            HistoryView(path: $path)
                        }
                    }
            }
            .environment(history)
            // Dùng khi chạy thử tự động: mở app với tham số "-openVideo <ID>"
            .task {
                if let id = UserDefaults.standard.string(forKey: "openVideo"), path.isEmpty {
                    path = [.player(id)]
                }
            }
            .preferredColorScheme(.dark)
            .tint(.red)
            // Mở bằng link: ltube://watch?v=ID (dùng khi thử trên giả lập) hoặc link YouTube
            .onOpenURL { url in
                if let id = YouTubeLinks.videoID(from: url.absoluteString) { path = [.player(id)] }
            }
        }
    }
}

/// Lấy ID video từ các dạng link YouTube (và ltube://watch?v=ID).
enum YouTubeLinks {
    static func videoID(from text: String) -> String? {
        let patterns = [
            #"[?&]v=([\w-]{11})"#,
            #"youtu\.be/([\w-]{11})"#,
            #"youtube\.com/(?:shorts|embed|live|v)/([\w-]{11})"#,
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                if let idRange = match.range(of: #"[\w-]{11}$"#, options: .regularExpression) {
                    return String(match[idRange])
                }
            }
        }
        return nil
    }
}

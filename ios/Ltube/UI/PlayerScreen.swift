import AVKit
import SwiftUI

/// Logic màn hình xem video (tương đương PlayerViewModel bên Android).
@MainActor
@Observable
final class PlayerModel {
    enum State {
        case loading, ready(VideoDetail), error(String)
    }

    let videoID: String
    var state: State = .loading
    var playbackError: String?
    var resumedFrom: Double?
    let player = AVPlayer()

    private let youtube = YouTubeService()
    private var timeObserver: Any?
    private var history: HistoryStore?
    private var recorded = false

    init(videoID: String) {
        self.videoID = videoID
    }

    func start(history: HistoryStore) async {
        guard self.history == nil else { return }
        self.history = history
        await load()
    }

    func load() async {
        state = .loading
        do {
            let detail = try await youtube.detail(videoID: videoID)
            state = .ready(detail)

            // Xem dở thì phát tiếp; xem gần hết hoặc dưới 10 giây thì phát từ đầu
            var start: Double = 0
            if let entry = history?.entry(for: videoID), !entry.isFinished, entry.positionSeconds >= 10 {
                start = entry.positionSeconds
                resumedFrom = start
            }
            if !recorded {
                recorded = true
                history?.recordWatch(detail, position: start)
            }
            try await play(from: start)
        } catch {
            if case .loading = state { state = .error(error.localizedDescription) }
            else { playbackError = error.localizedDescription }
        }
    }

    private func play(from start: Double) async throws {
        let url = try await youtube.playbackURL(videoID: videoID)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if start > 0 { await player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        player.play()
        observeProgress()
    }

    /// Lưu vị trí đang xem mỗi 5 giây.
    private func observeProgress() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        }
    }

    func savePosition() {
        guard recorded else { return }
        let position = player.currentTime().seconds
        guard position.isFinite, position > 0 else { return }
        let duration = player.currentItem?.duration.seconds
        history?.updatePosition(videoID, position: position, duration: duration)
    }

    func restart() {
        resumedFrom = nil
        player.seek(to: .zero)
    }

    func stop() {
        savePosition()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}

struct PlayerScreen: View {
    let videoID: String
    @Binding var path: [Route]
    @Environment(HistoryStore.self) private var history
    @State private var model: PlayerModel
    @State private var descriptionExpanded = false

    init(videoID: String, path: Binding<[Route]>) {
        self.videoID = videoID
        _path = path
        _model = State(initialValue: PlayerModel(videoID: videoID))
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerViewController(player: model.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)

            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                VStack(spacing: 16) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Thử lại") { Task { await model.load() } }.buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let detail):
                info(detail)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start(history: history) }
        .onDisappear { model.stop() }
    }

    private func info(_ detail: VideoDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(detail.summary.title).font(.title3.weight(.semibold))
                MetaLine(video: detail.summary)
                DownloadSection(videoID: detail.summary.id, title: detail.summary.title)

                if let resumed = model.resumedFrom {
                    HStack {
                        Text("Đang xem tiếp từ \(Format.duration(Int(resumed)))").font(.subheadline)
                        Spacer()
                        Button("Xem từ đầu") { model.restart() }
                        Button("Đóng") { model.resumedFrom = nil }
                    }
                    .padding(12)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = model.playbackError {
                    Text(error).foregroundStyle(.red)
                }
                if !detail.description.isEmpty {
                    Text(detail.description)
                        .font(.subheadline)
                        .lineLimit(descriptionExpanded ? nil : 3)
                        .onTapGesture { descriptionExpanded.toggle() }
                }
                if !detail.related.isEmpty {
                    Text("Video tiếp theo").font(.headline).padding(.top, 12)
                    ForEach(detail.related) { video in
                        Button {
                            // Thay video đang xem (không chồng nhiều trình phát)
                            model.stop()
                            if !path.isEmpty { path.removeLast() }
                            path.append(.player(video.id))
                        } label: {
                            CompactVideoRow(video: video, progress: history.progress(of: video.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Trình phát gốc của iOS: có nút toàn màn hình, Picture-in-Picture, điều khiển trên màn hình khoá.
struct PlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}

import SwiftUI

/// Nút "Tải về máy (MP4)", chọn chất lượng, tiến độ, và sau khi xong: Lưu vào Ảnh / Chia sẻ.
struct DownloadSection: View {
    let videoID: String
    let title: String
    @Environment(VideoDownloader.self) private var downloader

    @State private var choices: [DownloadChoice] = []
    @State private var loadingChoices = false
    @State private var showChoices = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch downloader.state(for: videoID) {
            case .idle, .failed:
                Button {
                    Task { await loadChoices() }
                } label: {
                    Label(loadingChoices ? "Đang lấy chất lượng..." : "Tải về máy (MP4)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(loadingChoices)

                if case .failed(let error) = downloader.state(for: videoID) {
                    Text("Tải thất bại: \(error)").font(.caption).foregroundStyle(.red)
                }

            case .preparing:
                HStack {
                    ProgressView()
                    Text("Đang chuẩn bị tải...").font(.subheadline)
                    Spacer()
                    Button("Huỷ") { downloader.cancel(videoID: videoID) }
                }

            case .downloading(let progress):
                VStack(alignment: .leading) {
                    HStack {
                        Text("Đang tải \(Int(progress * 100))% (giữ Ltube mở cho đến khi xong)")
                            .font(.subheadline)
                        Spacer()
                        Button("Huỷ") { downloader.cancel(videoID: videoID) }
                    }
                    ProgressView(value: progress)
                }

            case .merging:
                HStack {
                    ProgressView()
                    Text("Đang ghép hình và tiếng...").font(.subheadline)
                }

            case .done(let file):
                Text("Đã tải xong. File nằm trong app Tệp › Trên iPhone › Ltube.")
                    .font(.caption)
                    .foregroundStyle(.green)
                HStack {
                    Button {
                        Task {
                            do {
                                try await VideoDownloader.saveToPhotos(file)
                                message = "Đã lưu vào Ảnh."
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Lưu vào Ảnh", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: file) {
                        Label("Chia sẻ", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        // Chỉ dùng khi chạy thử tự động: mở app với "-autoDownload 720" để tự tải chất lượng đó
        .task {
            guard let wanted = UserDefaults.standard.string(forKey: "autoDownload").flatMap(Int.init),
                  case .idle = downloader.state(for: videoID),
                  let list = try? await downloader.choices(videoID: videoID),
                  let choice = list.first(where: { $0.height == wanted }) ?? list.first else { return }
            downloader.start(videoID: videoID, title: title, choice: choice)
        }
        .confirmationDialog("Tải về máy (MP4)", isPresented: $showChoices, titleVisibility: .visible) {
            ForEach(choices) { choice in
                Button(choice.label) {
                    message = nil
                    downloader.start(videoID: videoID, title: title, choice: choice)
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Chọn chất lượng. File MP4 có cả hình và tiếng.")
        }
    }

    private func loadChoices() async {
        loadingChoices = true
        defer { loadingChoices = false }
        do {
            choices = try await downloader.choices(videoID: videoID)
            if choices.isEmpty {
                message = "Video này chưa có bản MP4 để tải."
            } else {
                showChoices = true
            }
        } catch {
            message = LtubeError.youtube(error).localizedDescription
        }
    }
}

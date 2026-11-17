import AVFoundation
import Foundation
import Observation
import Photos
import UIKit
import YouTubeKit

/// Một lựa chọn tải về MP4 (giống DownloadOption bên Android).
struct DownloadChoice: Identifiable, Hashable {
    let height: Int
    /// Luồng hình (nếu `audioURL` == nil thì đây là file có sẵn cả hình lẫn tiếng).
    let videoURL: URL
    let audioURL: URL?
    var id: Int { height }
    var label: String { "\(height)p" }
}

/// Tải video thành file MP4 có hình + tiếng, lưu vào app Tệp (Trên iPhone › Ltube),
/// có thể lưu thêm vào Ảnh. Tương đương data/download bên Android.
@MainActor
@Observable
final class VideoDownloader {
    enum State: Equatable {
        case idle
        case preparing
        case downloading(Double)
        case merging
        case done(URL)
        case failed(String)
    }

    /// Trạng thái tải theo từng video.
    private(set) var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func state(for videoID: String) -> State { states[videoID] ?? .idle }

    // MARK: - Lựa chọn chất lượng

    /// Chỉ chọn hình H.264 + tiếng AAC để file MP4 mở được trên mọi thiết bị.
    nonisolated func choices(videoID: String) async throws -> [DownloadChoice] {
        let streams = try await YouTube(videoID: videoID, methods: [.local]).streams

        let audio = streams
            .filter { !$0.includesVideoTrack && Self.isAAC($0.audioCodec) }
            .max { ($0.averageBitrate ?? $0.bitrate ?? 0) < ($1.averageBitrate ?? $1.bitrate ?? 0) }

        var result: [Int: DownloadChoice] = [:]
        // File có sẵn hình + tiếng (thường 360p): tải thẳng, ưu tiên khi trùng độ phân giải
        for s in streams where s.isProgressive && s.fileExtension == .mp4 && Self.isH264(s.videoCodec) {
            if let h = s.videoResolution { result[h] = DownloadChoice(height: h, videoURL: s.url, audioURL: nil) }
        }
        if let audio {
            for s in streams where !s.includesAudioTrack && s.fileExtension == .mp4 && Self.isH264(s.videoCodec) {
                guard let h = s.videoResolution, h <= 1080, result[h] == nil else { continue }
                result[h] = DownloadChoice(height: h, videoURL: s.url, audioURL: audio.url)
            }
        }
        return result.values.sorted { $0.height > $1.height }
    }

    private nonisolated static func isH264(_ codec: YouTubeKit.VideoCodec?) -> Bool {
        switch codec {
        case .some(.avc1): return true
        default: return false
        }
    }

    private nonisolated static func isAAC(_ codec: YouTubeKit.AudioCodec?) -> Bool {
        switch codec {
        case .some(.mp4a): return true
        default: return false
        }
    }

    // MARK: - Tải

    func start(videoID: String, title: String, choice: DownloadChoice) {
        guard tasks[videoID] == nil else { return }
        states[videoID] = .preparing
        tasks[videoID] = Task {
            // Xin iOS cho chạy thêm một lúc khi người dùng chuyển app khác
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "download-\(videoID)")
            defer {
                UIApplication.shared.endBackgroundTask(bgTask)
                tasks[videoID] = nil
            }
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(videoID)")
                try? FileManager.default.removeItem(at: work)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

                let videoFile = work.appendingPathComponent("video.mp4")
                let parts = choice.audioURL == nil ? 1.0 : 2.0
                try await ChunkDownloader.download(choice.videoURL, to: videoFile) { p in
                    self.states[videoID] = .downloading(p / parts)
                }

                var finalFile = videoFile
                if let audioURL = choice.audioURL {
                    let audioFile = work.appendingPathComponent("audio.m4a")
                    try await ChunkDownloader.download(audioURL, to: audioFile) { p in
                        self.states[videoID] = .downloading(0.5 + p / 2)
                    }
                    states[videoID] = .merging
                    finalFile = work.appendingPathComponent("merged.mp4")
                    try await Mp4Merger.merge(video: videoFile, audio: audioFile, output: finalFile)
                }

                let saved = try Self.moveToDocuments(finalFile, title: title)
                try? FileManager.default.removeItem(at: work)
                states[videoID] = .done(saved)
            } catch is CancellationError {
                states[videoID] = .idle
            } catch {
                states[videoID] = .failed(error.localizedDescription)
            }
        }
    }

    func cancel(videoID: String) {
        tasks[videoID]?.cancel()
    }

    /// Lưu vào thư mục Documents của app: hiện trong app Tệp › Trên iPhone › Ltube.
    private static func moveToDocuments(_ file: URL, title: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = safeFileName(title)
        var target = docs.appendingPathComponent(base + ".mp4")
        var n = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = docs.appendingPathComponent("\(base) (\(n)).mp4")
            n += 1
        }
        try FileManager.default.moveItem(at: file, to: target)
        return target
    }

    static func safeFileName(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")).joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(80)).isEmpty ? "video" : String(cleaned.prefix(80))
    }

    // MARK: - Lưu vào Ảnh

    /// Lưu video vào ứng dụng Ảnh (iOS hỏi quyền lần đầu).
    static func saveToPhotos(_ file: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw DownloadError.photosDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: file)
        }
    }
}

enum DownloadError: LocalizedError {
    case http(Int)
    case photosDenied
    case mergeFailed(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Máy chủ YouTube trả lỗi \(code). Thử lại sau."
        case .photosDenied: return "Chưa cho phép Ltube lưu vào Ảnh. Bật trong Cài đặt › Ltube › Ảnh."
        case .mergeFailed(let message): return "Không ghép được hình và tiếng: \(message)"
        }
    }
}

/// Tải từng đoạn 10 MB bằng header Range (YouTube bóp tốc độ nếu tải cả file một lần).
enum ChunkDownloader {
    private static let chunkSize: Int64 = 10 * 1024 * 1024

    static func download(_ url: URL, to file: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        var offset: Int64 = 0
        var total: Int64? = nil
        while total == nil || offset < total! {
            try Task.checkCancellation()
            let end = offset + chunkSize - 1
            var request = URLRequest(url: url)
            request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            let (data, response) = try await fetchWithRetry(request)

            if total == nil {
                // "Content-Range: bytes 0-10485759/123456789" -> tổng dung lượng
                let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range")
                total = range.flatMap { $0.split(separator: "/").last }.flatMap { Int64($0) } ?? Int64(data.count)
            }
            try handle.write(contentsOf: data)
            offset += Int64(data.count)
            if data.isEmpty { break }
            let fraction = Double(offset) / Double(max(total ?? 1, 1))
            await progress(min(fraction, 1))
        }
    }

    private static func fetchWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<4 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw DownloadError.http(http.statusCode)
                }
                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
            }
        }
        throw lastError
    }
}

/// Ghép file hình + file tiếng thành MP4, chỉ đóng gói lại (không mã hoá lại).
enum Mp4Merger {
    static func merge(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw DownloadError.mergeFailed("thiếu luồng hình hoặc tiếng")
        }
        let duration = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compVideo?.insertTimeRange(range, of: videoTrack, at: .zero)
        let audioDuration = try await audioAsset.load(.duration)
        try compAudio?.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero
        )
        compVideo?.preferredTransform = try await videoTrack.load(.preferredTransform)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw DownloadError.mergeFailed("không tạo được phiên xuất file")
        }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = .mp4
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        if export.status != .completed {
            throw DownloadError.mergeFailed(export.error?.localizedDescription ?? "lỗi không rõ")
        }
    }
}

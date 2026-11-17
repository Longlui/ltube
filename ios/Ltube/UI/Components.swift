import SwiftUI

/// Ảnh thu nhỏ có thời lượng và thanh tiến độ đã xem.
struct Thumbnail: View {
    let video: VideoSummary
    var progress: Double?
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(white: 0.16)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()

            if video.durationSeconds > 0 {
                Text(Format.duration(video.durationSeconds))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(6)
            }
            if let progress, progress > 0 {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.35))
                            Rectangle().fill(.red).frame(width: geo.size.width * progress)
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Ô video cỡ lớn (lưới kết quả, hàng trên trang chủ).
struct VideoCard: View {
    let video: VideoSummary
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Thumbnail(video: video, progress: progress)
            Text(video.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            MetaLine(video: video)
        }
        .foregroundStyle(.primary)
    }
}

/// Dòng video gọn: ảnh nhỏ bên trái, chữ bên phải.
struct CompactVideoRow: View {
    let video: VideoSummary
    var progress: Double?
    var subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(video: video, progress: progress, cornerRadius: 8).frame(width: 168)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                MetaLine(video: video)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
    }
}

struct MetaLine: View {
    let video: VideoSummary
    var body: some View {
        Text([video.channelName, Format.views(video.viewCount)].filter { !$0.isEmpty }.joined(separator: " • "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Hàng video vuốt ngang có tiêu đề.
struct VideoRow: View {
    let title: String
    let videos: [VideoSummary]
    var progressOf: (VideoSummary) -> Double? = { _ in nil }
    var actionLabel: String?
    var onAction: () -> Void = {}
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                if let actionLabel { Button(actionLabel, action: onAction) }
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(videos) { video in
                        Button { onOpen(video.id) } label: {
                            VideoCard(video: video, progress: progressOf(video)).frame(width: 260)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

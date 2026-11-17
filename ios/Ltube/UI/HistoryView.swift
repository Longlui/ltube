import SwiftUI

/// Lịch sử xem, nhóm theo ngày (tương đương HistoryScreen bên Android).
struct HistoryView: View {
    @Binding var path: [Route]
    @Environment(HistoryStore.self) private var history
    @State private var confirmClear = false

    private var groups: [(label: String, entries: [WatchHistoryEntry])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        var result: [(String, [WatchHistoryEntry])] = []
        for entry in history.entries {
            let label: String
            if calendar.isDateInToday(entry.lastWatchedAt) { label = "Hôm nay" }
            else if calendar.isDateInYesterday(entry.lastWatchedAt) { label = "Hôm qua" }
            else { label = formatter.string(from: entry.lastWatchedAt) }
            if let index = result.firstIndex(where: { $0.0 == label }) { result[index].1.append(entry) }
            else { result.append((label, [entry])) }
        }
        return result.map { (label: $0.0, entries: $0.1) }
    }

    var body: some View {
        Group {
            if history.entries.isEmpty {
                Text("Chưa có video nào.\nVideo bạn xem sẽ hiện ở đây để xem tiếp.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(32)
            } else {
                List {
                    ForEach(groups, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.entries) { entry in
                                Button { path.append(.player(entry.id)) } label: {
                                    CompactVideoRow(
                                        video: entry.video,
                                        progress: entry.progress,
                                        subtitle: entry.isFinished ? "Đã xem hết"
                                            : entry.positionSeconds > 0
                                            ? "Đã xem tới \(Format.duration(Int(entry.positionSeconds)))" : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Xoá", role: .destructive) { history.delete(entry.id) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Lịch sử xem")
        .toolbar {
            if !history.entries.isEmpty {
                Button("Xoá tất cả") { confirmClear = true }
            }
        }
        .confirmationDialog("Xoá toàn bộ lịch sử?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) { history.clear() }
        } message: {
            Text("Danh sách xem tiếp và đề xuất cũng sẽ bị xoá. Không khôi phục được.")
        }
    }
}

import SwiftUI

struct TrendingRow: Identifiable {
    let kind: TrendingKind
    let videos: [VideoSummary]
    var id: String { kind.rawValue }
}

/// Logic trang chủ (tương đương HomeViewModel bên Android).
@MainActor
@Observable
final class HomeModel {
    enum SearchState {
        case idle, loading, results([VideoSummary]), error(String)
    }

    var config = RemoteConfig.default
    var trending: [TrendingRow] = []
    var feedLoading = true
    var search: SearchState = .idle
    var selectedTopic: String?
    var update: IOSRelease?

    private let youtube = YouTubeService()
    private let configService = RemoteConfigService()
    private var searchTask: Task<Void, Never>?
    private var loaded = false

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    func loadOnce() async {
        guard !loaded else { return }
        loaded = true
        await refresh()
    }

    func refresh() async {
        feedLoading = true
        config = await configService.load()
        if let release = config.iosRelease, release.build > Self.currentBuild { update = release }

        trending = await withTaskGroup(of: TrendingRow?.self) { group in
            for kind in config.trending {
                group.addTask { [youtube] in
                    guard let videos = try? await youtube.trending(kind), !videos.isEmpty else { return nil }
                    return TrendingRow(kind: kind, videos: Array(videos.prefix(20)))
                }
            }
            var rows: [TrendingRow] = []
            for await row in group { if let row { rows.append(row) } }
            // Giữ đúng thứ tự trong cấu hình
            return config.trending.compactMap { kind in rows.first { $0.kind == kind } }
        }
        feedLoading = false
    }

    /// Bấm tìm: nếu là link YouTube thì trả về ID để mở luôn.
    func submit(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = YouTubeLinks.videoID(from: trimmed) { return id }
        selectedTopic = nil
        runSearch(trimmed)
        return nil
    }

    func selectTopic(_ name: String, query: String) {
        if selectedTopic == name { clearSearch(); return }
        selectedTopic = name
        runSearch(query)
    }

    func clearSearch() {
        searchTask?.cancel()
        selectedTopic = nil
        search = .idle
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        search = .loading
        searchTask = Task {
            do {
                let results = try await youtube.search(query)
                if !Task.isCancelled { search = .results(results) }
            } catch {
                if !Task.isCancelled { search = .error(error.localizedDescription) }
            }
        }
    }
}

struct HomeView: View {
    @Binding var path: [Route]
    @Environment(HistoryStore.self) private var history
    @State private var model = HomeModel()
    @State private var query = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            topicChips
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadOnce() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Tìm hoặc dán link YouTube", text: $query)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        if let id = model.submit(query) { path.append(.player(id)) }
                    }
                if !query.isEmpty || !isIdle {
                    Button { query = ""; model.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))

            Button { path.append(.history) } label: {
                Image(systemName: "clock.arrow.circlepath").font(.title2)
            }
            .accessibilityLabel("Lịch sử xem")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.config.topics, id: \.name) { topic in
                    let selected = model.selectedTopic == topic.name
                    Button(topic.name) {
                        query = ""
                        model.selectTopic(topic.name, query: topic.query)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(selected ? Color.white.opacity(0.9) : Color(white: 0.16), in: Capsule())
                    .foregroundStyle(selected ? .black : .primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var isIdle: Bool {
        if case .idle = model.search { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.search {
        case .idle:
            feed
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            infoText(message)
        case .results(let videos):
            if videos.isEmpty {
                infoText("Không tìm thấy video nào.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(videos) { video in
                            Button { path.append(.player(video.id)) } label: {
                                VideoCard(video: video, progress: history.progress(of: video.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let update = model.update { updateBanner(update) }

                let continueWatching = history.continueWatching
                if !continueWatching.isEmpty {
                    VideoRow(
                        title: "▶ Xem tiếp",
                        videos: continueWatching.map(\.video),
                        progressOf: { history.progress(of: $0.id) },
                        actionLabel: "Lịch sử",
                        onAction: { path.append(.history) },
                        onOpen: { path.append(.player($0)) }
                    )
                }
                let recommendations = history.recommendations()
                if !recommendations.isEmpty {
                    VideoRow(title: "✨ Đề xuất cho bạn", videos: recommendations,
                             progressOf: { history.progress(of: $0.id) },
                             onOpen: { path.append(.player($0)) })
                }
                ForEach(model.trending) { row in
                    VideoRow(title: row.kind.title, videos: row.videos,
                             progressOf: { history.progress(of: $0.id) },
                             onOpen: { path.append(.player($0)) })
                }
                if model.feedLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(24)
                } else if continueWatching.isEmpty && recommendations.isEmpty && model.trending.isEmpty {
                    infoText("Gõ từ khoá rồi bấm tìm, chọn một chủ đề,\nhoặc dán link YouTube để xem ngay.")
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await model.refresh() }
    }

    private func updateBanner(_ release: IOSRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Có bản mới Ltube \(release.version)").font(.headline)
            ForEach(release.notes, id: \.self) { Text("• \($0)").font(.subheadline) }
            Text("Tải file .ipa rồi cài lại bằng Sideloadly như lần đầu.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Để sau") { model.update = nil }
                Button("Tải bản mới") { openURL(release.ipaURL) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import Foundation

/// Holds the lyrics of the current track and which line is active.
@MainActor
final class LyricsController: ObservableObject {
    enum Phase: Equatable { case idle, loading, synced, plain, instrumental, notFound }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainText: String = ""
    @Published private(set) var activeIndex: Int = -1
    /// Positive = lyrics appear earlier, negative = later (seconds).
    @Published private(set) var offset: Double = 0

    private var trackID: String?
    private var loadTask: Task<Void, Never>?
    private var lastTime: Double = 0
    /// Output latency of the current audio route (seconds). What the user hears is this much behind the
    /// player clock (Bluetooth: ~0.2 s), so the lyrics are held back by the same amount.
    private var latency: Double = 0

    func load(track: Track, offset: Double) {
        trackID = track.id
        self.offset = offset
        loadTask?.cancel()
        phase = .loading
        lines = []
        plainText = ""
        activeIndex = -1
        loadTask = Task { [weak self] in
            let result = await LyricsService.shared.lyrics(for: track)
            guard let self = self, !Task.isCancelled, self.trackID == track.id else { return }
            self.apply(result)
        }
    }

    func setOffset(_ value: Double) {
        offset = value
        tick(lastTime)
    }

    func setLatency(_ value: Double) {
        latency = value
        tick(lastTime)
    }

    func choose(_ candidate: LyricsCandidate, for track: Track) {
        Task { [weak self] in
            await LyricsService.shared.choose(candidate, for: track.id)
            guard let self = self, self.trackID == track.id else { return }
            self.apply(LyricsService.result(from: candidate))
        }
    }

    func tick(_ time: Double) {
        lastTime = time
        guard phase == .synced else { return }
        let idx = LRCParser.activeIndex(in: lines, at: time - latency + offset)
        if idx != activeIndex { activeIndex = idx }
    }

    private func apply(_ result: LyricsResult) {
        switch result {
        case .synced(let l):
            lines = l
            phase = .synced
            activeIndex = -1
            tick(lastTime)
        case .plain(let text):
            plainText = text
            phase = .plain
        case .instrumental:
            phase = .instrumental
        case .notFound:
            phase = .notFound
        }
    }
}

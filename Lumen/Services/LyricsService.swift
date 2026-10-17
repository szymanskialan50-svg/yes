import Foundation

struct LyricsCandidate: Identifiable, Codable, Equatable {
    var id: Int
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?

    var title: String { trackName ?? "" }
    var artist: String { artistName ?? "" }
    var hasSynced: Bool { !(syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPlain: Bool { !(plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum LyricsResult: Equatable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
}

/// Fetches time-synced lyrics from LRCLIB (https://lrclib.net) and caches them on disk.
actor LyricsService {
    static let shared = LyricsService()

    private var memory: [String: LyricsCandidate] = [:]
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = ["User-Agent": "MusicPlayer/1.0 (iOS music player)"]
        session = URLSession(configuration: cfg)
    }

    // MARK: Public

    func lyrics(for track: Track) async -> LyricsResult {
        if let c = memory[track.id] ?? readCache(track.id) {
            memory[track.id] = c
            return LyricsService.result(from: c)
        }
        guard let found = await find(track) else { return .notFound }
        memory[track.id] = found
        writeCache(found, id: track.id)
        return LyricsService.result(from: found)
    }

    func search(query: String) async -> [LyricsCandidate] {
        let list = (try? await request(["q": query])) ?? []
        return Array(list.filter { $0.hasSynced || $0.hasPlain || $0.instrumental == true }.prefix(25))
    }

    func choose(_ candidate: LyricsCandidate, for trackID: String) {
        memory[trackID] = candidate
        writeCache(candidate, id: trackID)
    }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: LyricsService.cacheDir)
    }

    static func result(from c: LyricsCandidate) -> LyricsResult {
        if c.hasSynced {
            let lines = LRCParser.parse(c.syncedLyrics ?? "")
            if !lines.isEmpty { return .synced(lines) }
        }
        if c.hasPlain { return .plain(c.plainLyrics ?? "") }
        if c.instrumental == true { return .instrumental }
        return .notFound
    }

    // MARK: Matching

    private func find(_ track: Track) async -> LyricsCandidate? {
        var best: (score: Double, cand: LyricsCandidate)? = nil
        let guesses = TitleCleaner.guesses(title: track.title, channel: track.artist)

        for g in guesses {
            guard let results = try? await request(["track_name": g.title, "artist_name": g.artist]) else { continue }
            if let hit = pick(results, guess: g, duration: track.duration), hit.score > (best?.score ?? -1) {
                best = hit
            }
            if let b = best, b.score >= 120 { break }
        }
        if best == nil, let first = guesses.first {
            if let results = try? await request(["q": "\(first.artist) \(first.title)"]),
               let hit = pick(results, guess: first, duration: track.duration) {
                best = hit
            }
        }
        return best?.cand
    }

    private func pick(_ results: [LyricsCandidate], guess: TitleCleaner.Guess, duration: Double) -> (score: Double, cand: LyricsCandidate)? {
        var best: (score: Double, cand: LyricsCandidate)? = nil
        for c in results {
            let titleSim = TitleCleaner.similarity(c.title, guess.title)
            if titleSim < 0.34 { continue }
            let artistSim = TitleCleaner.similarity(c.artist, guess.artist)
            var score = 0.0
            if c.hasSynced { score += 100 } else if c.hasPlain { score += 40 } else if c.instrumental == true { score += 20 } else { continue }
            score += titleSim * 30 + artistSim * 20
            // Wersja tekstu z innym czasem trwania niż film = tekst rozjeżdża się z piosenką.
            // Dlatego zgodność czasu trwania liczy się mocno: ±1 s prawie bez kary, a każda sekunda więcej boli.
            if duration > 0, let d = c.duration, d > 0 {
                let diff = abs(d - duration)
                score -= diff <= 1.5 ? diff : 1.5 + min(diff - 1.5, 60) * 3
            }
            if score > (best?.score ?? -Double.infinity) { best = (score, c) }
        }
        return best
    }

    // MARK: Network

    private func request(_ params: [String: String]) async throws -> [LyricsCandidate] {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let qs = params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        guard let url = URL(string: "https://lrclib.net/api/search?\(qs)") else { return [] }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode([LyricsCandidate].self, from: data)) ?? []
    }

    // MARK: Disk cache

    private static var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LumenLyrics", isDirectory: true)
    }

    private func fileURL(_ id: String) -> URL {
        LyricsService.cacheDir.appendingPathComponent("\(id).json")
    }

    private func readCache(_ id: String) -> LyricsCandidate? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        return try? JSONDecoder().decode(LyricsCandidate.self, from: data)
    }

    private func writeCache(_ c: LyricsCandidate, id: String) {
        try? FileManager.default.createDirectory(at: LyricsService.cacheDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(c) { try? data.write(to: fileURL(id), options: .atomic) }
    }
}

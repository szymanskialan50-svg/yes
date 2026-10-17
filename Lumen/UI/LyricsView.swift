import SwiftUI

/// Apple Music style synced lyrics: big bold lines, active line sharp, others dimmed and blurred.
struct LyricsView: View {
    @ObservedObject var lyrics: LyricsController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine: PlayerEngine

    private let anchor = UnitPoint(x: 0, y: 0.22)

    var body: some View {
        switch lyrics.phase {
        case .synced:
            synced.id(engine.currentTrack?.id ?? "none")
        case .plain:
            ScrollView(showsIndicators: false) {
                Text(lyrics.plainText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                Spacer().frame(height: 30)
            }
        case .idle, .loading:
            VStack { Spacer(); ProgressView().tint(Color.primary); Spacer() }
                .frame(maxWidth: .infinity)
        case .instrumental:
            message("Utwór instrumentalny", "music.note")
        case .notFound:
            message("Nie znaleziono tekstu", "text.quote")
        }
    }

    private func message(_ text: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon).font(.system(size: 34, weight: .semibold))
            Text(text).font(.system(size: 22, weight: .bold))
            Spacer()
        }
        .foregroundStyle(Color.primary.opacity(0.7))
        .frame(maxWidth: .infinity)
    }

    private var synced: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Spacer().frame(height: 30)
                    ForEach(lyrics.lines) { line in
                        LyricLineView(text: line.text,
                                      distance: abs(line.id - lyrics.activeIndex),
                                      isActive: line.id == lyrics.activeIndex,
                                      fontSize: 34,
                                      blurOn: settings.data.blurInactiveLyrics) {
                            engine.seek(to: max(0, line.time - lyrics.offset))
                        }
                        .id(line.id)
                    }
                    Spacer().frame(height: 280)
                }
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.10),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: lyrics.activeIndex) { _, newIndex in
                guard newIndex >= 0 else { return }
                withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                    proxy.scrollTo(newIndex, anchor: anchor)
                }
            }
            .onAppear {
                if lyrics.activeIndex >= 0 { proxy.scrollTo(lyrics.activeIndex, anchor: anchor) }
            }
        }
    }
}

struct LyricLineView: View {
    let text: String
    let distance: Int
    let isActive: Bool
    let fontSize: Double
    let blurOn: Bool
    let onTap: () -> Void

    var body: some View {
        Text(text.isEmpty ? "• • •" : text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isActive ? 1 : (distance > 5 ? 0.25 : 0.38))
            // Blur is expensive: only the few lines near the active one get it.
            .blur(radius: (blurOn && !isActive && distance <= 5) ? CGFloat(min(distance, 4)) * 1.5 : 0)
            .scaleEffect(isActive ? 1 : 0.95, anchor: .leading)
            .animation(distance <= 6 ? .easeInOut(duration: 0.35) : nil, value: isActive)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }
}

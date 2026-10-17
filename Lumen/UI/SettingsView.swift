import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var toast: ToastCenter
    @State private var showGuide = false

    private let rowBackground = Color.primary.opacity(0.09)

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Ustawienia")
            Form {
                helpSection
                backgroundSection
                lyricsSection
                playerSection
            }
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showGuide) {
            GuideView { showGuide = false }
                .preferredColorScheme(settings.colorScheme)
        }
    }

    // MARK: Sections

    private var helpSection: some View {
        Section {
            Button {
                showGuide = true
            } label: {
                Label("Jak korzystać z aplikacji", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } footer: {
            Text("Krótki przewodnik krok po kroku dla początkujących.")
        }
        .listRowBackground(rowBackground)
    }

    private var backgroundSection: some View {
        Section {
            Picker("Tło", selection: $settings.data.theme) {
                ForEach(ThemeMode.allCases) { m in Text(m.title).tag(m) }
            }
            .pickerStyle(.segmented)
            if settings.data.theme == .blur {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Przyciemnienie").font(.subheadline)
                    Slider(value: $settings.data.dim, in: 0...0.8)
                }
            }
        } header: {
            Text("Tło")
        } footer: {
            Text("Kolorowy blur powstaje z okładki grającej piosenki i bardzo powoli się porusza.")
        }
        .listRowBackground(rowBackground)
    }

    private var lyricsSection: some View {
        Section("Teksty piosenek") {
            Toggle("Rozmywaj nieaktywne linijki", isOn: $settings.data.blurInactiveLyrics)
            Button("Wyczyść pamięć podręczną tekstów") {
                Task {
                    await LyricsService.shared.clearCache()
                    toast.show("Wyczyszczono pamięć podręczną tekstów")
                }
            }
        }
        .listRowBackground(rowBackground)
    }

    private var playerSection: some View {
        Section {
            Button("Odśwież strumień bieżącej piosenki") {
                engine.reloadPlayer()
                toast.show("Pobieram strumień od nowa")
            }
            Button("Wyczyść pamięć adresów strumieni") {
                Task {
                    await StreamResolver.shared.clear()
                    toast.show("Wyczyszczono pamięć strumieni")
                }
            }
        } header: {
            Text("Odtwarzacz")
        } footer: {
            Text("Dźwięk jest pobierany bezpośrednio z YouTube (YouTubeKit) i gra natywnym odtwarzaczem iOS, dzięki czemu działa w tle i na zablokowanym ekranie. Jeśli piosenka przestanie grać, odśwież strumień.")
        }
        .listRowBackground(rowBackground)
    }
}

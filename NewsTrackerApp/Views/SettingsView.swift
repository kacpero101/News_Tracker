import NewsCore
import SwiftUI

struct SettingsView: View {
    @Environment(NewsStore.self) private var store
    @State private var apiKeyInput = ""
    @State private var confirmClearCache = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Źródła") {
                    NavigationLink {
                        SourcesView()
                    } label: {
                        LabeledContent("Kanały RSS", value: "\(store.enabledSources.count)/\(store.sources.count)")
                    }
                }

                Section("Newsy") {
                    NavigationLink {
                        CategoriesSettingsView()
                    } label: {
                        LabeledContent("Kategorie", value: "\(store.allTopics.count)")
                    }
                    NavigationLink {
                        MutedNewsView()
                    } label: {
                        LabeledContent("Ignorowane słowa", value: "\(store.muteList.keywords.count)")
                    }
                }

                Section("Rynki") {
                    NavigationLink {
                        PriceAlertsSettingsView()
                    } label: {
                        Label("Powiadomienia o cenach", systemImage: "bell.badge")
                    }
                }

                Section {
                    Toggle("Klasyfikacja i streszczenia AI", isOn: $store.aiEnabled)
                        .disabled(!store.hasAPIKey)

                    if store.hasAPIKey {
                        LabeledContent("Klucz API", value: "zapisany w Keychain")
                        Picker("Model", selection: $store.aiModel) {
                            ForEach(ClaudeArticleEnhancer.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        Button("Uruchom analizę teraz") { store.enhanceInBackground() }
                            .disabled(!store.aiEnabled || store.isEnhancing)
                        Button("Usuń klucz", role: .destructive) { store.deleteAPIKey() }
                    } else {
                        SecureField("Klucz API Claude (sk-ant-…)", text: $apiKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Zapisz klucz") {
                            store.saveAPIKey(apiKeyInput)
                            apiKeyInput = ""
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if let status = store.aiStatus {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI (opcjonalnie)")
                } footer: {
                    Text("Domyślnie wyłączone – aplikacja działa w pełni bez AI. Po włączeniu do Claude API wysyłany jest wyłącznie nagłówek i krótki opis z RSS (maks. 10 artykułów na odświeżenie). Wywołania API są płatne i rozliczane na Twoim koncie Anthropic. Klucz jest przechowywany tylko w pęku kluczy urządzenia.")
                }

                Section("Dane") {
                    Button("Wyczyść pamięć podręczną newsów", role: .destructive) {
                        confirmClearCache = true
                    }
                    .confirmationDialog("Usunąć zapisane newsy? Lista „Do przeczytania” zostanie zachowana.", isPresented: $confirmClearCache, titleVisibility: .visible) {
                        Button("Wyczyść", role: .destructive) {
                            Task { await store.clearCache() }
                        }
                    }
                }

                Section("Informacje") {
                    LabeledContent("Wersja", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    Text("Aplikacja pokazuje wyłącznie nagłówki, krótkie opisy i linki udostępniane przez wydawców w kanałach RSS. Pełne artykuły otwierane są na stronach wydawców.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ustawienia")
        }
    }
}

struct SourcesView: View {
    @Environment(NewsStore.self) private var store
    @State private var showsAddSource = false

    var body: some View {
        List {
            ForEach(Language.allCases, id: \.self) { language in
                Section("\(language.flag) \(language.displayName)") {
                    ForEach(store.sources.filter { $0.language == language }) { source in
                        SourceRow(source: source)
                            .swipeActions {
                                if store.isCustom(source) {
                                    Button(role: .destructive) {
                                        store.removeSource(source)
                                    } label: {
                                        Label("Usuń", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Źródła")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Odśwież") { Task { await store.refresh() } }
                    .disabled(store.isRefreshing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddSource = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Dodaj źródło")
                }
            }
        }
        .sheet(isPresented: $showsAddSource) {
            AddSourceView()
        }
    }
}

private struct SourceRow: View {
    @Environment(NewsStore.self) private var store
    let source: FeedSource

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.isEnabled(source) },
            set: { store.setEnabled($0, for: source) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(source.name)
                    if !source.verified {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Niezweryfikowane")
                    }
                    if store.isCustom(source) {
                        Text("własne")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                if let category = source.defaultCategory {
                    Text(category.displayName)
                        .font(.caption)
                        .foregroundStyle(category.color)
                }
                if let resolved = store.resolvedFeedURLs[source.id] {
                    Text("Kanał znaleziony na stronie: \(resolved.absoluteString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let failure = store.failure(for: source) {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

import NewsCore
import SwiftUI

/// "Ignore similar news": pick words from the headline; news containing them are hidden.
struct IgnoreSimilarView: View {
    @Environment(NewsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let article: Article
    private let suggestions: [String]

    @State private var selected: Set<String> = []
    @State private var customText = ""
    @State private var matchInflections = true
    @State private var hideThisArticle = true

    init(article: Article) {
        self.article = article
        suggestions = SimilarNewsSuggester.suggestions(for: article)
    }

    /// Keywords that will be muted, in headline order.
    private var keywords: [String] {
        let words = suggestions.filter(selected.contains).map { matchInflections ? SimilarNewsSuggester.stem($0) : $0 }
        return words + CustomCategory.parseKeywords(customText)
    }

    private var affectedCount: Int {
        guard !keywords.isEmpty else { return hideThisArticle ? 1 : 0 }
        var list = MuteList(keywords: keywords)
        if hideThisArticle { list.hiddenArticleIDs.insert(article.id) }
        let matcher = list.matcher()
        return store.visibleArticles.filter(matcher.isMuted).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("News") {
                    Text(article.title)
                        .font(.subheadline.weight(.semibold))
                    Text(article.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if suggestions.isEmpty {
                        Text("Brak charakterystycznych słów w nagłówku – wpisz własne poniżej.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(suggestions, id: \.self) { word in
                        Toggle(isOn: Binding(
                            get: { selected.contains(word) },
                            set: { isOn in
                                if isOn { selected.insert(word) } else { selected.remove(word) }
                            }
                        )) {
                            HStack {
                                Text(word)
                                if matchInflections, SimilarNewsSuggester.stem(word) != word {
                                    Text(SimilarNewsSuggester.stem(word))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    TextField("Własne słowa, np. „przejazd*, wypadek”", text: $customText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Ukrywaj newsy zawierające")
                } footer: {
                    Text("Wystarczy jedno z wybranych słów w nagłówku lub opisie, żeby news został ukryty. Listę ignorowanych słów zmienisz w Ustawieniach.")
                }

                Section {
                    Toggle("Uwzględnij odmiany słów", isOn: $matchInflections)
                    Toggle("Ukryj też ten news", isOn: $hideThisArticle)
                } footer: {
                    Text("Odmiany: „Iranu” → iran* (Iran, Iranu, irański).")
                }

                Section {
                    Label("Zostanie ukrytych: \(affectedCount)", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ignoruj podobne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ignoruj") {
                        store.mute(keywords: keywords, hiding: hideThisArticle ? article : nil)
                        dismiss()
                    }
                    .disabled(keywords.isEmpty && !hideThisArticle)
                }
            }
        }
    }
}

/// Settings: muted keywords and hidden news.
struct MutedNewsView: View {
    @Environment(NewsStore.self) private var store
    @State private var newKeyword = ""

    var body: some View {
        List {
            Section {
                ForEach(store.muteList.keywords, id: \.self) { keyword in
                    Text(keyword)
                }
                .onDelete { offsets in
                    for keyword in offsets.map({ store.muteList.keywords[$0] }) {
                        store.unmute(keyword: keyword)
                    }
                }
                HStack {
                    TextField("Dodaj słowo, np. wypadek*", text: $newKeyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addKeyword)
                    Button("Dodaj", action: addKeyword)
                        .disabled(CustomCategory.parseKeywords(newKeyword).isEmpty)
                }
            } header: {
                Text("Ignorowane słowa")
            } footer: {
                Text("News z którymkolwiek z tych słów w nagłówku lub opisie jest ukryty. Przesuń w lewo, aby usunąć. Gwiazdka dopasowuje odmiany.")
            }

            Section {
                LabeledContent("Ukryte pojedyncze newsy", value: "\(store.muteList.hiddenArticleIDs.count)")
                Button("Przywróć ukryte newsy") {
                    store.restoreHiddenArticles()
                }
                .disabled(store.muteList.hiddenArticleIDs.isEmpty)
            } footer: {
                Text("Obecnie ukrytych z listy newsów: \(store.hiddenCount).")
            }
        }
        .navigationTitle("Ignorowane")
    }

    private func addKeyword() {
        let keywords = CustomCategory.parseKeywords(newKeyword)
        guard !keywords.isEmpty else { return }
        store.mute(keywords: keywords, hiding: nil)
        newKeyword = ""
    }
}

/// Settings: list of custom categories.
struct CategoriesSettingsView: View {
    @Environment(NewsStore.self) private var store
    @State private var editorTarget: CategoryEditorTarget?

    var body: some View {
        List {
            Section {
                ForEach(store.customCategories) { category in
                    Button {
                        editorTarget = CategoryEditorTarget(category: category)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            TopicBadge(topic: category.topic)
                            Text(category.keywords.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.customCategories[$0] }
                    Task {
                        for category in removed {
                            await store.deleteCategory(category)
                        }
                    }
                }
                Button {
                    editorTarget = CategoryEditorTarget(category: nil)
                } label: {
                    Label("Dodaj kategorię", systemImage: "plus.circle")
                }
            } header: {
                Text("Własne kategorie")
            } footer: {
                Text("Własne kategorie pojawiają się obok wbudowanych w pasku nad listą newsów. Newsy trafiają do nich według słów kluczowych.")
            }

            Section("Wbudowane") {
                ForEach(Topic.builtIn, id: \.self) { topic in
                    TopicBadge(topic: topic)
                }
            }
        }
        .navigationTitle("Kategorie")
        .sheet(item: $editorTarget) { target in
            CategoryEditorView(original: target.category)
        }
    }
}

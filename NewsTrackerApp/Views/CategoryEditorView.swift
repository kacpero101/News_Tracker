import NewsCore
import SwiftUI

/// Sheet target for creating (nil) or editing a custom category.
struct CategoryEditorTarget: Identifiable {
    let id = UUID()
    let category: CustomCategory?
}

/// Create or edit a user-defined news category.
struct CategoryEditorView: View {
    @Environment(NewsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let original: CustomCategory?

    @State private var name: String
    @State private var keywordsText: String
    @State private var symbol: String
    @State private var color: String
    @State private var matchCount: Int?
    @State private var isSaving = false

    init(original: CustomCategory?) {
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _keywordsText = State(initialValue: original?.keywords.joined(separator: ", ") ?? "")
        _symbol = State(initialValue: original?.symbol ?? "tag")
        _color = State(initialValue: original?.color ?? "teal")
    }

    private var keywords: [String] { CustomCategory.parseKeywords(keywordsText) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nazwa") {
                    TextField("np. Drony, Energetyka, Sport", text: $name)
                }

                Section {
                    TextField("np. dron*, drone*, Drohne*", text: $keywordsText, axis: .vertical)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let matchCount {
                        Label("Pasuje do \(matchCount) z \(store.articles.count) pobranych newsów", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Słowa kluczowe")
                } footer: {
                    Text("Oddziel przecinkami lub nowymi liniami. Gwiazdka dopasowuje odmiany: „dron*” → dron, drona, drony. Wielkość liter i polskie znaki nie mają znaczenia. Słowa działają dla newsów w każdym języku, więc dodaj też odpowiedniki angielskie i niemieckie.")
                }

                Section("Ikona") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(CategoryPalette.symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(symbol == item ? CategoryPalette.color(named: color).opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(symbol == item ? CategoryPalette.color(named: color) : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                            .accessibilityAddTraits(symbol == item ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Kolor") {
                    HStack(spacing: 10) {
                        ForEach(CategoryPalette.colors) { entry in
                            Button {
                                color = entry.name
                            } label: {
                                Circle()
                                    .fill(entry.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if color == entry.name {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(entry.name)
                            .accessibilityAddTraits(color == entry.name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Podgląd") {
                    Label(trimmedName.isEmpty ? "Nowa kategoria" : trimmedName, systemImage: symbol)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(CategoryPalette.color(named: color), in: Capsule())
                        .foregroundStyle(.white)
                }

                if let original {
                    Section {
                        Button("Usuń kategorię", role: .destructive) {
                            Task {
                                await store.deleteCategory(original)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "Nowa kategoria" : "Edycja kategorii")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty || keywords.isEmpty || isSaving)
                }
            }
            .task(id: keywordsText) {
                // Debounced preview of how many downloaded news match the keywords.
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                matchCount = keywords.isEmpty ? nil : countMatches(keywords)
            }
        }
    }

    private func countMatches(_ keywords: [String]) -> Int {
        let preview = CustomCategory(id: "preview", name: "preview", keywords: keywords)
        let classifier = TopicClassifier(keywords: KeywordList(topics: [:]).merging([preview]))
        return store.articles.filter {
            !classifier.keywordTopics(title: $0.title, summary: $0.summary, language: $0.language).isEmpty
        }.count
    }

    private func save() {
        isSaving = true
        let category = CustomCategory(
            id: original?.id,
            name: trimmedName,
            keywords: keywords,
            symbol: symbol,
            color: color
        )
        Task {
            await store.saveCategory(category)
            dismiss()
        }
    }
}

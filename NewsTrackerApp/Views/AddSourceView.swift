import NewsCore
import SwiftUI

/// Finds RSS/Atom feeds for a site address (e.g. "pb.pl", "gpw.pl/_rss") and adds one as a source.
struct AddSourceView: View {
    @Environment(NewsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var results: [DiscoveredFeed] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var selected: DiscoveredFeed?
    @State private var name = ""
    @State private var language: Language = .polish
    @State private var category: Topic?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Adres strony lub kanału, np. pb.pl", text: $address)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if isSearching {
                            ProgressView()
                        } else {
                            Button {
                                Task { await search() }
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Szukaj kanałów")
                        }
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Znajdź kanał RSS")
                } footer: {
                    Text("Wpisz adres serwisu (np. pb.pl, spidersweb.pl), stronę z listą kanałów (np. gpw.pl/_rss) albo bezpośredni adres kanału. Aplikacja sprawdzi stronę i pokaże znalezione kanały.")
                }

                if !results.isEmpty {
                    Section("Znalezione kanały") {
                        ForEach(results) { feed in
                            Button {
                                select(feed)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(feed.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(feed.url.absoluteString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(summary(of: feed))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if selected?.url == feed.url {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if selected != nil {
                    Section {
                        TextField("Nazwa", text: $name)
                        Picker("Język", selection: $language) {
                            ForEach(Language.allCases, id: \.self) { language in
                                Text("\(language.flag) \(language.displayName)").tag(language)
                            }
                        }
                        Picker("Kategoria", selection: $category) {
                            Text("Brak – tylko słowa kluczowe").tag(Topic?.none)
                            ForEach(store.allTopics, id: \.self) { topic in
                                Text(topic.displayName).tag(Topic?.some(topic))
                            }
                        }
                    } header: {
                        Text("Ustawienia źródła")
                    } footer: {
                        Text("Kategorię wybierz tylko wtedy, gdy kanał dotyczy wyłącznie jednego tematu (np. kryptowaluty). Dla serwisów ogólnych zostaw „Brak” – tematy przypiszą słowa kluczowe.")
                    }
                }
            }
            .navigationTitle("Dodaj źródło")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dodaj") { add() }
                        .disabled(selected == nil || trimmedName.isEmpty)
                }
            }
        }
    }

    private func summary(of feed: DiscoveredFeed) -> String {
        let count = "\(feed.itemCount) wpisów"
        guard let first = feed.sampleTitles.first, !first.isEmpty else { return count }
        return count + " · np. „" + first + "”"
    }

    private func search() async {
        guard FeedDiscovery.normalizedURL(from: address) != nil else {
            message = "Nieprawidłowy adres."
            return
        }
        isSearching = true
        defer { isSearching = false }
        message = "Szukam kanałów…"
        selected = nil
        results = await FeedDiscoverer().discover(address)
        if results.isEmpty {
            message = "Nie znaleziono kanału RSS pod tym adresem. Spróbuj adresu strony „RSS” serwisu (zwykle link w stopce strony)."
        } else {
            message = results.count == 1 ? "Znaleziono kanał:" : "Znaleziono \(results.count) kanały – wybierz jeden:"
            if results.count == 1 {
                select(results[0])
            }
        }
    }

    private func select(_ feed: DiscoveredFeed) {
        let previousTitle = selected?.title
        selected = feed
        if trimmedName.isEmpty || name == previousTitle {
            name = feed.title
        }
    }

    private func add() {
        guard let feed = selected else { return }
        guard !store.hasSource(url: feed.url) else {
            message = "Ten kanał jest już na liście źródeł."
            return
        }
        let source = FeedSource(
            id: "user-" + UUID().uuidString.prefix(8).lowercased(),
            name: trimmedName,
            url: feed.url,
            language: language,
            defaultCategory: category,
            verified: true
        )
        Task { await store.addSource(source) }
        dismiss()
    }
}

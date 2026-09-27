import NewsCore
import SwiftUI

struct ReadingListView: View {
    @Environment(NewsStore.self) private var store
    @State private var presentedArticle: Article?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                ForEach(store.filteredReadingList) { article in
                    ArticleListRow(article: article, presentedArticle: $presentedArticle, context: .readingList)
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.filteredReadingList[$0] }
                    Task {
                        for article in removed {
                            await store.toggleSaved(article)
                        }
                    }
                }

                if !store.readingList.isEmpty && !store.readArchive.isEmpty {
                    NavigationLink {
                        ReadArchiveView()
                    } label: {
                        Label("Archiwum przeczytanych: \(store.readArchive.count)", systemImage: "archivebox")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !store.readingList.isEmpty {
                    TopicChips(selection: $store.readingListTopics)
                }
            }
            .overlay {
                if store.readingList.isEmpty {
                    ContentUnavailableView {
                        Label("Wszystko przeczytane", systemImage: "bookmark")
                    } description: {
                        Text("Dotknij ikony zakładki przy newsie albo przesuń go w lewo, aby zapisać do przeczytania. Przeczytane oznaczysz zielonym ✓.")
                    } actions: {
                        if !store.readArchive.isEmpty {
                            NavigationLink("Archiwum przeczytanych (\(store.readArchive.count))") {
                                ReadArchiveView()
                            }
                        }
                    }
                } else if store.filteredReadingList.isEmpty {
                    ContentUnavailableView {
                        Label("Brak zapisanych w tej kategorii", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Wybierz inną kategorię.")
                    } actions: {
                        Button("Pokaż wszystkie") { store.readingListTopics = [] }
                    }
                }
            }
            .navigationTitle("Do przeczytania")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ReadArchiveView()
                    } label: {
                        Label("Archiwum przeczytanych", systemImage: "archivebox")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.readingList.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(item: $presentedArticle) { article in
                SafariView(url: article.link)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Archive of news marked as read, grouped by the day they were read.
struct ReadArchiveView: View {
    @Environment(NewsStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var presentedArticle: Article?
    @State private var searchText = ""
    @State private var confirmClear = false

    private var entries: [ReadArticle] {
        let query = ArticleQuery(searchText: searchText)
        return store.readArchive.filter { query.matches($0.article) }
    }

    var body: some View {
        let groups = DayGrouping.group(entries) { $0.readAt }
        List {
            ForEach(groups, id: \.day) { group in
                Section(DayTitle.string(for: group.day)) {
                    ForEach(group.items) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Szukaj w przeczytanych")
        .overlay {
            if store.readArchive.isEmpty {
                ContentUnavailableView(
                    "Archiwum jest puste",
                    systemImage: "archivebox",
                    description: Text("News oznaczony jako przeczytany (zielony ✓ na liście „Do przeczytania”) trafia tutaj i nie jest już liczony do przeczytania.")
                )
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Przeczytane")
        .toolbar {
            if !store.readArchive.isEmpty {
                Button("Wyczyść", role: .destructive) {
                    confirmClear = true
                }
            }
        }
        .confirmationDialog("Wyczyścić archiwum przeczytanych?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Wyczyść archiwum (\(store.readArchive.count))", role: .destructive) {
                Task { await store.clearReadArchive() }
            }
        }
        .sheet(item: $presentedArticle) { article in
            SafariView(url: article.link)
                .ignoresSafeArea()
        }
    }

    private func row(for entry: ReadArticle) -> some View {
        ArticleRow(
            article: entry.article,
            isSaved: false,
            onToggleSaved: { Task { await store.restoreToReadingList(entry) } }
        )
        .onTapGesture {
            presentedArticle = entry.article
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await store.deleteFromArchive(ids: [entry.id]) }
            } label: {
                Label("Usuń", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await store.restoreToReadingList(entry) }
            } label: {
                Label("Do przeczytania", systemImage: "bookmark")
            }
            .tint(.accentColor)
        }
        .contextMenu {
            Button {
                Task { await store.restoreToReadingList(entry) }
            } label: {
                Label("Przywróć do przeczytania", systemImage: "bookmark")
            }
            Button {
                openURL(entry.article.link)
            } label: {
                Label("Otwórz w przeglądarce", systemImage: "safari")
            }
            ShareLink(item: entry.article.link) {
                Label("Udostępnij", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                Task { await store.deleteFromArchive(ids: [entry.id]) }
            } label: {
                Label("Usuń z archiwum", systemImage: "trash")
            }
        }
    }
}

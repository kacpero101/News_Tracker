import NewsCore
import SwiftUI

struct NewsListView: View {
    @Environment(NewsStore.self) private var store
    @State private var presentedArticle: Article?
    @State private var categoryEditor: CategoryEditorTarget?
    @State private var categoryToDelete: CustomCategory?
    @State private var articleToMute: Article?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                if let error = store.configurationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if !store.failures.isEmpty {
                    FailuresBanner(failures: store.failures)
                }
                ForEach(store.filteredArticles) { article in
                    ArticleListRow(article: article, presentedArticle: $presentedArticle, onIgnoreSimilar: { article in
                        articleToMute = article
                    })
                }
                if store.hiddenCount > 0 {
                    NavigationLink {
                        MutedNewsView()
                    } label: {
                        Label("Ukryte newsy: \(store.hiddenCount)", systemImage: "eye.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                TopicChips(
                    selection: $store.query.topics,
                    onAddCategory: { categoryEditor = CategoryEditorTarget(category: nil) },
                    onEditCategory: { categoryEditor = CategoryEditorTarget(category: $0) },
                    onDeleteCategory: { categoryToDelete = $0 }
                )
            }
            .overlay { emptyState }
            .navigationTitle("News Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $store.query.searchText, prompt: "Szukaj w nagłówkach i opisach")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.isRefreshing {
                        ProgressView()
                    } else if let lastRefresh = store.lastRefresh {
                        Text(lastRefresh, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    LanguageFilterMenu()
                }
            }
            .sheet(item: $presentedArticle) { article in
                SafariView(url: article.link)
                    .ignoresSafeArea()
            }
            .sheet(item: $categoryEditor) { target in
                CategoryEditorView(original: target.category)
            }
            .sheet(item: $articleToMute) { article in
                IgnoreSimilarView(article: article)
            }
            .confirmationDialog(
                "Usunąć kategorię?",
                isPresented: Binding(
                    get: { categoryToDelete != nil },
                    set: { if !$0 { categoryToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: categoryToDelete
            ) { category in
                Button("Usuń „\(category.name)”", role: .destructive) {
                    Task { await store.deleteCategory(category) }
                }
            } message: { _ in
                Text("Newsy nie zostaną usunięte – przestaną tylko być oznaczane tą kategorią.")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.filteredArticles.isEmpty && !store.isRefreshing {
            if store.articles.isEmpty {
                ContentUnavailableView {
                    Label("Brak newsów", systemImage: "newspaper")
                } description: {
                    Text("Przeciągnij w dół, aby pobrać najnowsze wiadomości.")
                } actions: {
                    Button("Odśwież") { Task { await store.refresh() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if !store.query.searchText.isEmpty {
                ContentUnavailableView.search(text: store.query.searchText)
            } else {
                ContentUnavailableView {
                    Label("Brak wyników", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Żaden artykuł nie pasuje do wybranych filtrów.")
                } actions: {
                    Button("Wyczyść filtry") { store.clearFilters() }
                }
            }
        }
    }
}

/// A row with tap-to-open, "read later" / "read" buttons, swipe actions and a context menu.
struct ArticleListRow: View {
    enum Context {
        case news, readingList
    }

    @Environment(NewsStore.self) private var store
    @Environment(\.openURL) private var openURL
    let article: Article
    @Binding var presentedArticle: Article?
    var context: Context = .news
    /// Enables "ignore similar" and "hide" actions (news list only).
    var onIgnoreSimilar: ((Article) -> Void)?

    /// "Mark as read" button action, shown on the reading list only.
    private var markReadAction: (() -> Void)? {
        guard context == .readingList else { return nil }
        return { Task { await store.markRead(article) } }
    }

    var body: some View {
        let saved = store.isSaved(article)
        let read = store.isRead(article)
        ArticleRow(
            article: article,
            isSaved: saved,
            onToggleSaved: { Task { await store.toggleSaved(article) } },
            isRead: context == .news && read,
            onMarkRead: markReadAction
        )
        .onTapGesture {
            presentedArticle = article
            store.didOpen(article)
        }
        .accessibilityAction(named: "Otwórz artykuł") {
            presentedArticle = article
            store.didOpen(article)
        }
        .swipeActions(edge: .trailing) {
            Button {
                Task { await store.toggleSaved(article) }
            } label: {
                Label(saved ? "Usuń z listy" : "Do przeczytania", systemImage: saved ? "bookmark.slash" : "bookmark")
            }
            .tint(saved ? Color.gray : Color.accentColor)
        }
        .swipeActions(edge: .leading) {
            if context == .readingList {
                Button {
                    Task { await store.markRead(article) }
                } label: {
                    Label("Przeczytane", systemImage: "checkmark.circle")
                }
                .tint(.green)
            } else if let onIgnoreSimilar {
                Button {
                    onIgnoreSimilar(article)
                } label: {
                    Label("Ignoruj podobne", systemImage: "eye.slash")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            Button {
                Task { await store.toggleSaved(article) }
            } label: {
                Label(saved ? "Usuń z listy" : "Zapisz do przeczytania", systemImage: saved ? "bookmark.slash" : "bookmark")
            }
            if read {
                Button {
                    Task { await store.markUnread(article) }
                } label: {
                    Label("Oznacz jako nieprzeczytany", systemImage: "circle")
                }
            } else {
                Button {
                    Task { await store.markRead(article) }
                } label: {
                    Label("Oznacz jako przeczytany", systemImage: "checkmark.circle")
                }
            }
            if let onIgnoreSimilar {
                Button {
                    onIgnoreSimilar(article)
                } label: {
                    Label("Ignoruj podobne…", systemImage: "eye.slash")
                }
                Button {
                    store.hide(article)
                } label: {
                    Label("Ukryj ten news", systemImage: "xmark.circle")
                }
            }
            Button {
                openURL(article.link)
                store.didOpen(article)
            } label: {
                Label("Otwórz w przeglądarce", systemImage: "safari")
            }
            ShareLink(item: article.link) {
                Label("Udostępnij", systemImage: "square.and.arrow.up")
            }
        }
    }
}

private struct FailuresBanner: View {
    let failures: [SourceFailure]

    var body: some View {
        DisclosureGroup {
            ForEach(failures) { failure in
                VStack(alignment: .leading) {
                    Text(failure.sourceName).font(.subheadline.bold())
                    Text(failure.message).font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(
                "Niedostępne źródła: \(failures.count)",
                systemImage: "exclamationmark.icloud"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }
}

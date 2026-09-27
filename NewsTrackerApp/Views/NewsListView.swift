import NewsCore
import SwiftUI

struct NewsListView: View {
    @Environment(NewsStore.self) private var store
    @State private var presentedArticle: Article?

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
                    ArticleListRow(article: article, presentedArticle: $presentedArticle)
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                TopicFilterBar()
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

/// A row with tap-to-open, swipe-to-save and a context menu.
struct ArticleListRow: View {
    @Environment(NewsStore.self) private var store
    @Environment(\.openURL) private var openURL
    let article: Article
    @Binding var presentedArticle: Article?

    var body: some View {
        let saved = store.isSaved(article)
        Button {
            presentedArticle = article
        } label: {
            ArticleRow(article: article, isSaved: saved)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button {
                Task { await store.toggleSaved(article) }
            } label: {
                Label(saved ? "Usuń z listy" : "Do przeczytania", systemImage: saved ? "bookmark.slash" : "bookmark")
            }
            .tint(saved ? Color.gray : Color.accentColor)
        }
        .contextMenu {
            Button {
                Task { await store.toggleSaved(article) }
            } label: {
                Label(saved ? "Usuń z listy" : "Zapisz do przeczytania", systemImage: saved ? "bookmark.slash" : "bookmark")
            }
            Button {
                openURL(article.link)
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

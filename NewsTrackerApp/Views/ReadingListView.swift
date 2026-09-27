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
                    ArticleListRow(article: article, presentedArticle: $presentedArticle)
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.filteredReadingList[$0] }
                    Task {
                        for article in removed {
                            await store.toggleSaved(article)
                        }
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
                    ContentUnavailableView(
                        "Lista jest pusta",
                        systemImage: "bookmark",
                        description: Text("Dotknij ikony zakładki przy newsie albo przesuń go w lewo, aby zapisać do przeczytania.")
                    )
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
                if !store.readingList.isEmpty {
                    EditButton()
                }
            }
            .sheet(item: $presentedArticle) { article in
                SafariView(url: article.link)
                    .ignoresSafeArea()
            }
        }
    }
}

import NewsCore
import SwiftUI

struct ReadingListView: View {
    @Environment(NewsStore.self) private var store
    @State private var presentedArticle: Article?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.readingList) { article in
                    ArticleListRow(article: article, presentedArticle: $presentedArticle)
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.readingList[$0] }
                    Task {
                        for article in removed {
                            await store.toggleSaved(article)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if store.readingList.isEmpty {
                    ContentUnavailableView(
                        "Lista jest pusta",
                        systemImage: "bookmark",
                        description: Text("Przesuń artykuł w lewo, aby zapisać go do przeczytania.")
                    )
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

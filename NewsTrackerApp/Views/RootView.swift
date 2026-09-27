import SwiftUI

struct RootView: View {
    @Environment(NewsStore.self) private var store

    var body: some View {
        TabView {
            NewsListView()
                .tabItem { Label("Newsy", systemImage: "newspaper") }

            MarketsView()
                .tabItem { Label("Rynki", systemImage: "chart.line.uptrend.xyaxis") }

            ReadingListView()
                .tabItem { Label("Do przeczytania", systemImage: "bookmark") }
                .badge(store.readingList.count)

            SettingsView()
                .tabItem { Label("Ustawienia", systemImage: "gearshape") }
        }
        .alert(
            "Błąd",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(store.errorMessage ?? "") }
        )
    }
}
